-- GCDOptimizer_Core.lua
-- Retail 12.1.5 bootstrap, validated SavedVariables, segment lifecycle,
-- combat automation, and the single authoritative /gcdopt dispatcher.

local ADDON_NAME, NS = ...
local U = NS.Util

NS.addonName = ADDON_NAME
NS.VERSION = "0.6.0-midnight-12.1.5"
NS.DB_SCHEMA = 2

local function Now()
  return GetTime()
end

local function SafeCall(object, method, ...)
  if not (object and type(object[method]) == "function") then return false end

  local ok, result = pcall(object[method], object, ...)
  if not ok then
    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
    if type(handler) == "function" then handler(result) end
  end
  return ok, result
end

local function MergeDefaults(destination, defaults)
  if type(destination) ~= "table" then destination = {} end
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      destination[key] = MergeDefaults(
        type(destination[key]) == "table" and destination[key] or {},
        value
      )
    elseif destination[key] == nil then
      destination[key] = value
    end
  end
  return destination
end

local OBSOLETE_SCHEMA1_KEYS = {
  "analysisUpdateInterval",
  "recommendMultiBadThr",
  "recommendSleepBadThr",
  "afkpMinSamples",
  "recommendDiffBadMs",
}

local function MigrateConfig(database)
  local schema = tonumber(database.__schemaVersion) or 0
  if schema < 2 then
    for index = 1, #OBSOLETE_SCHEMA1_KEYS do
      database[OBSOLETE_SCHEMA1_KEYS[index]] = nil
    end
  end
  return database
end

local DEFAULTS = {
  showHUD = true,
  hudUpdateInterval = 0.25,
  pollInterval = 0.05,
  statWindowN = 60,

  recommendMinSamples = 20,
  recommendLatencyFactor = 0.9,
  recommendMaxMs = 400,
  recommendStepMs = 5,
  recommendLeadBufferMs = nil,

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

  minimap = { hide = false },
  localeOverride = "auto",

  anchors = {
    enabled = true,
    fadeWindow = 0.25,
    maxEvents = 300,
    rules = {},
  },
}

local function ClampNumber(tableValue, key, minimum, maximum, fallback)
  local value = tonumber(tableValue[key])
  if not U.IsFiniteNumber(value) then value = fallback end
  tableValue[key] = U.Clamp(value, minimum, maximum)
end

local function SanitizeConfig(config)
  config.showHUD = config.showHUD ~= false
  config.autoStartCombat = config.autoStartCombat ~= false
  config.autoStopCombat = config.autoStopCombat ~= false
  config.dynamicMicroCap = config.dynamicMicroCap ~= false

  ClampNumber(config, "hudUpdateInterval", 0.10, 1.00, 0.25)
  ClampNumber(config, "pollInterval", 0.03, 0.25, 0.05)
  ClampNumber(config, "statWindowN", 20, 300, 60)
  ClampNumber(config, "recommendMinSamples", 5, 200, 20)
  ClampNumber(config, "recommendLatencyFactor", 0.25, 2.00, 0.9)
  ClampNumber(config, "recommendMaxMs", 50, 4000, 400)
  ClampNumber(config, "recommendStepMs", 1, 50, 5)
  if config.recommendLeadBufferMs ~= nil then
    local buffer = tonumber(config.recommendLeadBufferMs)
    config.recommendLeadBufferMs = U.IsFiniteNumber(buffer) and U.Clamp(buffer, 0, 500) or nil
  end
  ClampNumber(config, "sysDelayMinSamples", 3, 100, 6)
  ClampNumber(config, "sysDelayLatencyFactor", 0.10, 1.50, 0.50)
  ClampNumber(config, "pressBufferSeconds", 2, 30, 8)
  ClampNumber(config, "pressBufferMax", 100, 5000, 1200)
  ClampNumber(config, "microCap", 0.05, 1.00, 0.20)
  ClampNumber(config, "microCapMargin", 0, 0.50, 0.05)
  ClampNumber(config, "microCapMin", 0.05, 1.00, 0.10)
  ClampNumber(config, "microCapMax", config.microCapMin, 1.50, 0.40)

  if type(config.minimap) ~= "table" then config.minimap = { hide = false } end
  config.minimap.hide = config.minimap.hide == true
  local minimapPosition = tonumber(config.minimap.minimapPos)
  config.minimap.minimapPos = U.IsFiniteNumber(minimapPosition) and (minimapPosition % 360) or 225
  if type(config.localeOverride) ~= "string" then config.localeOverride = "auto" end
  if type(config.anchors) ~= "table" then config.anchors = {} end
  config.anchors = MergeDefaults(config.anchors, DEFAULTS.anchors)
  ClampNumber(config.anchors, "maxEvents", 50, 2000, 300)
  config.anchors.maxEvents = math.floor(config.anchors.maxEvents)
  ClampNumber(config.anchors, "fadeWindow", 0.05, 1.00, 0.25)
  return config
end

function NS:GetConfig()
  if type(NS.db) == "table" and _G.GCDOptimizerDB == NS.db then
    return NS.db
  end

  local database = _G.GCDOptimizerDB
  if type(database) ~= "table" then database = {} end
  database = MigrateConfig(database)
  database = SanitizeConfig(MergeDefaults(database, DEFAULTS))
  database.__schemaVersion = NS.DB_SCHEMA
  database.__addonVersion = NS.VERSION
  _G.GCDOptimizerDB = database
  NS.db = database
  return database
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
  local config = NS:GetConfig()
  config.showHUD = shown

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
  if not NS:GetConfig().showHUD then SafeCall(NS.HUD, "StopTicker") end
  return true
end

function NS:PauseSegment(now)
  now = now or Now()
  if not NS.state.inSegment then return false end

  local wasAutomatic = NS.state.autoCombat and true or false
  NS.state.inSegment = false
  NS.state.segmentEnd = now
  NS.state.segmentEndEffective = now
  NS.state.autoCombat = false
  NS.state.manualPaused = not wasAutomatic

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
  SafeCall(NS.GCDEstimator, "ResetSegment", now)
  SafeCall(NS.Metrics, "Reset", now)
  SafeCall(NS.Integrator, "Reset", now)
  SafeCall(NS.GCDDetector, "Reset", now)
  SafeCall(NS.Anchors, "Reset", now)
  SafeCall(NS.Failures, "Reset", now)
  SafeCall(NS.HUD, "StopTicker")
  SafeCall(NS.HUD, "Update", true)
end

function NS:ResetAndContinue(now)
  now = now or Now()
  local wasRunning = NS.state.inSegment
  local wasAutomatic = NS.state.autoCombat
  NS:ResetSegment(now)
  if wasRunning then
    NS.state.autoCombat = wasAutomatic
    NS:StartSegment(now)
  end
end

local function CheckpointAction()
  if NS.Metrics then
    SafeCall(NS.Integrator, "CheckpointAction", NS.Metrics:GetLastActionTime())
  end
end

function NS:OnGCDObservation(timestamp, duration, source)
  if not NS.state.inSegment then return end
  SafeCall(NS.Integrator, "Observe", timestamp, duration, source)
end

function NS:OnGCDObservationGap()
  if not NS.state.inSegment then return end
  SafeCall(NS.Metrics, "BreakContinuity")
end

function NS:OnPress(timestamp)
  if not NS.state.inSegment then return end
  if type(timestamp) ~= "number" then timestamp = Now() end
  SafeCall(NS.Metrics, "OnPress", timestamp)
  CheckpointAction()
end

local function MaybeReanchorExact(startTime, source)
  if source ~= U.GCD_SOURCE_DIRECT then return end
  local segmentStart = NS.state.segmentStart or startTime
  local lead = segmentStart - startTime
  if NS.state.autoCombat and lead > 0 and lead <= 2.0 then
    NS.state.segmentStart = startTime
    SafeCall(NS.Metrics, "ReanchorStart", startTime)
    SafeCall(NS.Integrator, "ReanchorStart", startTime)
  end
end

function NS:OnGCDStart(startTime, duration, source)
  if not NS.state.inSegment then return end
  source = source or U.GCD_SOURCE_CACHED

  if not NS.state.firstGCDSeen then
    NS.state.firstGCDSeen = true
    MaybeReanchorExact(startTime, source)
  end

  SafeCall(NS.GCDEstimator, "OnGCDStart", startTime, duration, source)
  SafeCall(NS.Metrics, "OnGCDStart", startTime, duration, source)
  CheckpointAction()
  SafeCall(NS.HUD, "OnGCDStart", startTime, duration, source)
end

function NS:OnGCDRefresh(startTime, duration, source)
  if not NS.state.inSegment then return end
  SafeCall(NS.Metrics, "RefreshLastGCD", startTime, duration, source)
  SafeCall(NS.HUD, "OnRateUpdate")
end

function NS:OnGCDUpgrade(oldStart, newStart, duration, source)
  if not NS.state.inSegment then return end
  MaybeReanchorExact(newStart, source)
  SafeCall(NS.GCDEstimator, "OnGCDStart", newStart, duration, source)
  SafeCall(NS.Metrics, "UpgradeLastGCD", oldStart, newStart, duration, source)
  CheckpointAction()
  SafeCall(NS.HUD, "OnGCDStart", newStart, duration, source)
end

function NS:OnRateUpdate()
  SafeCall(NS.HUD, "OnRateUpdate")
end

function NS:OnCombatStart()
  local config = NS:GetConfig()
  if not config.autoStartCombat then return end

  -- Explicit/manual tracking owns its segment; combat automation must not
  -- discard it or silently change its stop policy.
  if NS.state.inSegment then return end

  NS.state.autoCombat = true
  NS:StartSegment(Now())
end

function NS:OnCombatEnd()
  local config = NS:GetConfig()
  if config.autoStopCombat and NS.state.inSegment and NS.state.autoCombat then
    NS:PauseSegment(Now())
  end
end

function NS:Init()
  if NS._inited then return end
  NS._inited = true

  local config = NS:GetConfig()
  SafeCall(NS.GCDEstimator, "Init")
  SafeCall(NS.PressTracker, "Init")
  SafeCall(NS.GCDDetector, "Init")
  SafeCall(NS.Failures, "Init")
  SafeCall(NS.Anchors, "Init")

  NS:ResetSegment(Now())
  SafeCall(NS.HUD, "Init")
  SafeCall(NS.Options, "Init")
  SafeCall(NS.Minimap, "Init")
  NS:SetHUDShown(config.showHUD)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
  if event == "ADDON_LOADED" then
    if addonName == ADDON_NAME then NS:Init() end
  elseif event == "PLAYER_LOGIN" then
    NS:Init()
  elseif event == "PLAYER_ENTERING_WORLD" then
    NS:Init()
    -- Reloading during combat does not replay PLAYER_REGEN_DISABLED. Preserve
    -- a deliberate pause and an existing manual segment on later world entry.
    if not NS.state.manualPaused and InCombatLockdown and InCombatLockdown() then
      NS:OnCombatStart()
    end
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
  local estimator = NS.GCDEstimator and NS.GCDEstimator:DebugSnapshot() or {}
  local detector = NS.GCDDetector and NS.GCDDetector:DebugSnapshot() or {}
  local observations = NS.Metrics and NS.Metrics:GetObservationCounts() or {}
  Print(string.format(
    "version=%s gcd=%.3f source=%s direct=%d estimated=%d exactCycles=%d attributed=%d ambiguous=%d incomplete=%d status=%s",
    NS.VERSION,
    estimator.lastPred or 0,
    tostring(estimator.source or U.GCD_SOURCE_CACHED),
    observations.direct or 0,
    observations.estimated or 0,
    observations.exactCycles or 0,
    observations.attributable or 0,
    observations.ambiguous or 0,
    observations.incomplete or 0,
    tostring(detector.status or U.GCD_STATUS_UNAVAILABLE)
  ))
end

local function PrintAnchors()
  if not (NS.Anchors and NS.Anchors.GetRecentEvents) then
    Print("Anchors unavailable")
    return
  end

  local events = NS.Anchors:GetRecentEvents()
  if #events == 0 then
    Print("No anchor events")
    return
  end

  for index = math.max(1, #events - 14), #events do
    local data = events[index]
    local line = string.format("[%.3f] %s", tonumber(data.t) or 0, tostring(data.type or "?"))
    if data.overlaySpellID then line = line .. " spell=" .. tostring(data.overlaySpellID) end
    if data.confidence then line = line .. string.format(" confidence=%.2f", data.confidence) end
    if data.reason then line = line .. " (" .. tostring(data.reason) .. ")" end
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
  else
    PrintHelp()
  end
end
