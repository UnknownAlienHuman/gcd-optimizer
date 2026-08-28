-- GCDOptimizer_Core.lua
-- Retail 12.1 bootstrap, SavedVariables migration, segment lifecycle, combat
-- automation, and the single authoritative /gcdopt command dispatcher.

local ADDON_NAME, NS = ...

NS.addonName = ADDON_NAME
NS.VERSION = "0.5.0-midnight-12.1"
NS.DB_SCHEMA = 1

local function Now()
  return GetTime()
end

local function SafeCall(object, method, ...)
  if object and type(object[method]) == "function" then
    local ok = pcall(object[method], object, ...)
    return ok
  end
  return false
end

local function DeepCopyDefaults(destination, defaults)
  if type(destination) ~= "table" then destination = {} end
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      destination[key] = DeepCopyDefaults(
        type(destination[key]) == "table" and destination[key] or {},
        value
      )
    elseif destination[key] == nil then
      destination[key] = value
    end
  end
  return destination
end

local DEFAULTS = {
  showHUD = true,
  hudUpdateInterval = 0.25,
  analysisUpdateInterval = 5.0,
  pollInterval = 0.05,
  statWindowN = 60,

  recommendMinSamples = 20,
  recommendLatencyFactor = 0.9,
  recommendMaxMs = 400,
  recommendStepMs = 5,
  recommendLeadBufferMs = nil,
  recommendMultiBadThr = 0.15,
  recommendSleepBadThr = 0.15,
  recommendDiffBadMs = 60,

  afkpMinSamples = 5,
  sysDelayMinSamples = 6,
  sysDelayLatencyFactor = 0.50,

  autoStartCombat = true,
  autoStopCombat = true,

  pressBufferSeconds = 8.0,
  pressBufferMax = 1200,

  dynamicMicroCap = true,
  microCap = 0.20,
  microCapMargin = 0.05,
  microCapMin = 0.10,
  microCapMax = 0.40,

  minimap = {
    hide = false,
  },

  localeOverride = "auto",

  anchors = {
    enabled = true,
    fadeWindow = 0.25,
    maxEvents = 300,
    rules = {},
  },
}

function NS:GetConfig()
  local db = _G.GCDOptimizerDB
  if type(db) ~= "table" then db = {} end

  -- Version upgrades preserve compatible settings. Schema migrations, rather
  -- than the release string, own any future destructive transformation.
  db = DeepCopyDefaults(db, DEFAULTS)
  db.__schemaVersion = NS.DB_SCHEMA
  db.__addonVersion = NS.VERSION

  _G.GCDOptimizerDB = db
  NS.db = db
  return db
end

NS.state = NS.state or {
  inSegment = false,
  segmentStart = 0,
  segmentEnd = 0,
  segmentEndEffective = 0,
  autoCombat = false,
  manualPaused = false,
  firstGCDSeen = false,
}

function NS:SetHUDShown(shown)
  shown = shown and true or false
  local cfg = NS:GetConfig()
  cfg.showHUD = shown

  local hud = NS.HUD
  if hud and hud.frame then hud.frame:SetShown(shown) end

  if shown then
    SafeCall(hud, "StartTicker")
    SafeCall(hud, "Update", true)
  else
    SafeCall(hud, "StopTicker")
    if hud and hud.detailsFrame then hud.detailsFrame:Hide() end
  end
end

function NS:StartSegment(now)
  now = now or Now()
  if NS.state.inSegment then return false end

  NS.state.inSegment = true
  NS.state.segmentStart = now
  NS.state.segmentEnd = 0
  NS.state.segmentEndEffective = 0
  NS.state.manualPaused = false
  NS.state.firstGCDSeen = false

  SafeCall(NS.GCDEstimator, "OnSegmentStart", now)
  SafeCall(NS.PressTracker, "Reset")
  SafeCall(NS.Metrics, "OnSegmentStart", now)
  SafeCall(NS.Integrator, "OnSegmentStart", now)
  SafeCall(NS.GCDDetector, "OnSegmentStart", now)
  SafeCall(NS.Anchors, "OnSegmentStart", now)
  SafeCall(NS.Failures, "OnSegmentStart", now)
  SafeCall(NS.HUD, "OnSegmentStart", now)
  if not NS:GetConfig().showHUD then
    SafeCall(NS.HUD, "StopTicker")
  end
  return true
end

function NS:PauseSegment(now)
  now = now or Now()
  if not NS.state.inSegment then return false end

  local wasAutoCombat = NS.state.autoCombat and true or false
  NS.state.inSegment = false
  NS.state.segmentEnd = now
  NS.state.segmentEndEffective = now
  NS.state.autoCombat = false
  NS.state.manualPaused = not wasAutoCombat

  SafeCall(NS.GCDEstimator, "OnSegmentEnd", now)
  SafeCall(NS.Metrics, "OnSegmentEnd", now)
  if NS.Metrics and type(NS.Metrics.segmentEndEffective) == "number" then
    NS.state.segmentEndEffective = NS.Metrics.segmentEndEffective
  end
  SafeCall(NS.Integrator, "OnSegmentEnd", now)
  SafeCall(NS.GCDDetector, "OnSegmentEnd", now)
  SafeCall(NS.Anchors, "OnSegmentEnd", now)
  SafeCall(NS.Failures, "OnSegmentEnd", now)
  SafeCall(NS.HUD, "OnSegmentEnd", now)
  return true
end

function NS:ResetSegment(now)
  now = now or Now()

  NS.state.inSegment = false
  NS.state.segmentStart = now
  NS.state.segmentEnd = now
  NS.state.segmentEndEffective = now
  NS.state.autoCombat = false
  NS.state.manualPaused = false
  NS.state.firstGCDSeen = false

  SafeCall(NS.PressTracker, "Reset")
  SafeCall(NS.GCDEstimator, "Reset", now)
  SafeCall(NS.Metrics, "Reset", now)
  SafeCall(NS.Integrator, "Reset", now)
  SafeCall(NS.GCDDetector, "Reset", now)
  SafeCall(NS.Anchors, "Reset", now)
  SafeCall(NS.Failures, "Reset", now)
  SafeCall(NS.HUD, "Update", true)
end

function NS:ResetAndContinue(now)
  now = now or Now()
  local wasRunning = NS.state.inSegment
  local wasAutoCombat = NS.state.autoCombat

  NS:ResetSegment(now)
  if wasRunning then
    NS.state.autoCombat = wasAutoCombat
    NS:StartSegment(now)
  end
end

function NS:OnPress(timestamp)
  if not NS.state.inSegment then return end
  if type(timestamp) ~= "number" then timestamp = Now() end
  SafeCall(NS.Metrics, "OnPress", timestamp)
end

function NS:OnGCDStart(startTime, duration)
  if not NS.state.inSegment then return end

  if not NS.state.firstGCDSeen then
    NS.state.firstGCDSeen = true
    local segmentStart = NS.state.segmentStart or startTime
    local lead = segmentStart - startTime
    if NS.state.autoCombat and lead > 0 and lead <= 2.0 then
      NS.state.segmentStart = startTime
      SafeCall(NS.Metrics, "ReanchorStart", startTime)
      SafeCall(NS.Integrator, "ReanchorStart", startTime)
    end
  end

  SafeCall(NS.GCDEstimator, "OnGCDStart", startTime, duration)
  SafeCall(NS.Metrics, "OnGCDStart", startTime, duration)
  SafeCall(NS.HUD, "OnGCDStart")
end

function NS:OnRateUpdate()
  SafeCall(NS.HUD, "OnRateUpdate")
end

function NS:OnCombatStart()
  local cfg = NS:GetConfig()
  if not cfg.autoStartCombat then return end

  if NS.state.inSegment then
    if NS.state.autoCombat then return end
    NS:ResetSegment(Now())
  end

  NS.state.autoCombat = true
  NS:StartSegment(Now())
end

function NS:OnCombatEnd()
  local cfg = NS:GetConfig()
  if not cfg.autoStopCombat then return end
  if NS.state.inSegment and NS.state.autoCombat then
    NS:PauseSegment(Now())
  end
end

function NS:Init()
  if NS._inited then return end
  NS._inited = true

  local cfg = NS:GetConfig()

  SafeCall(NS.GCDEstimator, "Init")
  SafeCall(NS.PressTracker, "Init")
  SafeCall(NS.GCDDetector, "Init")
  SafeCall(NS.Failures, "Init")
  SafeCall(NS.Anchors, "Init")

  NS:ResetSegment(Now())

  SafeCall(NS.HUD, "Init")
  if NS.HUD and NS.HUD.frame and type(NS.HUD.frame.HookScript) == "function" and not NS.HUD._coreVisibilityHooked then
    NS.HUD._coreVisibilityHooked = true
    NS.HUD.frame:HookScript("OnHide", function()
      if not NS:GetConfig().showHUD then
        SafeCall(NS.HUD, "StopTicker")
        if NS.HUD.detailsFrame then NS.HUD.detailsFrame:Hide() end
      end
    end)
  end
  SafeCall(NS.Options, "Init")
  SafeCall(NS.Minimap, "Init")
  NS:SetHUDShown(cfg.showHUD)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
  if event == "ADDON_LOADED" then
    if addonName == ADDON_NAME then NS:Init() end
  elseif event == "PLAYER_LOGIN" then
    NS:Init()
  elseif event == "PLAYER_REGEN_DISABLED" then
    NS:OnCombatStart()
  elseif event == "PLAYER_REGEN_ENABLED" then
    NS:OnCombatEnd()
  end
end)

local function Print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGCDOpt|r " .. tostring(message))
  end
end

local function PrintHelp()
  Print("/gcdopt — toggle HUD")
  Print("/gcdopt show | hide | start | stop | reset")
  Print("/gcdopt minimap show | minimap hide")
  Print("/gcdopt debug | anchors | help")
end

local function PrintDebug()
  if not (NS.GCDEstimator and NS.GCDEstimator.DebugSnapshot) then
    Print("Estimator unavailable")
    return
  end

  local snapshot = NS.GCDEstimator:DebugSnapshot()
  Print(string.format(
    "version=%s gcd=%.3f source=%s samples=%d",
    NS.VERSION,
    snapshot.lastPred or 0,
    tostring(snapshot.source or "unknown"),
    snapshot.sampleCount or 0
  ))
end

local function PrintAnchors()
  if not (NS.Anchors and NS.Anchors.GetRecentEvents) then
    Print("Anchors unavailable")
    return
  end

  local events = NS.Anchors:GetRecentEvents()
  local first = math.max(1, #events - 14)
  if #events == 0 then
    Print("No anchor events")
    return
  end

  for i = first, #events do
    local eventData = events[i]
    local line = string.format(
      "[%.3f] %s",
      tonumber(eventData.t) or 0,
      tostring(eventData.type or "?")
    )
    if eventData.overlaySpellID then
      line = line .. " spell=" .. tostring(eventData.overlaySpellID)
    end
    if eventData.confidence then
      line = line .. string.format(" confidence=%.2f", eventData.confidence)
    end
    if eventData.reason then
      line = line .. " (" .. tostring(eventData.reason) .. ")"
    end
    Print(line)
  end
end

SLASH_GCDOPT1 = "/gcdopt"
SlashCmdList.GCDOPT = function(rawMessage)
  local message = (rawMessage or ""):lower():match("^%s*(.-)%s*$")
  local command, argument = message:match("^(%S+)%s*(.-)$")

  if not command or command == "" then
    NS:SetHUDShown(not NS:GetConfig().showHUD)
  elseif command == "show" then
    NS:SetHUDShown(true)
  elseif command == "hide" then
    NS:SetHUDShown(false)
  elseif command == "start" then
    NS.state.autoCombat = false
    NS:StartSegment(Now())
  elseif command == "stop" then
    NS.state.autoCombat = false
    NS:PauseSegment(Now())
  elseif command == "reset" then
    NS:ResetAndContinue(Now())
  elseif command == "minimap" then
    if argument == "show" and NS.Minimap then
      NS.Minimap:SetIconShown(true)
    elseif argument == "hide" and NS.Minimap then
      NS.Minimap:SetIconShown(false)
    else
      Print("Usage: /gcdopt minimap show | hide")
    end
  elseif command == "debug" then
    PrintDebug()
  elseif command == "anchors" then
    PrintAnchors()
  elseif command == "help" then
    PrintHelp()
  else
    PrintHelp()
  end
end
