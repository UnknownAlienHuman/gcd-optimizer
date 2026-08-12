-- GCDOptimizer_Core.lua
-- Core bootstrap + SavedVariables + combat autostart + segment lifecycle.
-- Integrates Failures module (Init + segment hooks).

local ADDON_NAME, NS = ...

NS.addonName = ADDON_NAME
NS.VERSION = "0.4.9-midnight-v2"

-- ---------- helpers ----------
local function SafeCall(obj, method, ...)
  if obj and type(obj[method]) == "function" then
    local ok, err = pcall(obj[method], obj, ...)
    if not ok then
      -- Do not hard-error; keep addon running.
      -- If you want debug prints, add a config flag and print here.
    end
  end
end

local function DeepCopyDefaults(dst, src)
  if type(dst) ~= "table" then dst = {} end
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = DeepCopyDefaults(type(dst[k]) == "table" and dst[k] or {}, v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

local function Now()
  return GetTime()
end

-- ---------- defaults ----------
local DEFAULTS = {
  showHUD = true,
  hudUpdateInterval = 0.25, -- ticker update (fast)
  analysisUpdateInterval = 5.0, -- recompute analytics/recommendations (seconds)
  statWindowN = 60,         -- deque sizes for p90/median etc

  -- SpellQueueWindow recommendation
  recommendMinSamples = 20,
  recommendLatencyFactor = 0.9,  -- lower bound = latency * factor
  recommendMaxMs = 400,
  recommendStepMs = 5,

  -- AFKp display threshold: require enough AFK-gap samples to avoid 0/100% noise.
  afkpMinSamples = 5,
  recommendLeadBufferMs = nil,   -- nil = auto from median lead
  recommendMultiBadThr = 0.15,
  recommendSleepBadThr = 0.15,
  recommendDiffBadMs = 60,

  -- segment / combat
  autoStartCombat = true,
  autoStopCombat = true,

  -- presses buffer (used by Metrics:OnPress)
  -- Midnight: management/AFK diagnostics need longer history to detect "pressing during gaps".
  pressBufferSeconds = 8.0,
  pressBufferMax = 1200,

  -- microcap logic
  dynamicMicroCap = true,
  microCap = 0.20,        -- used only if dynamicMicroCap=false
  microCapMargin = 0.05,  -- MCap = SQW + margin (clamped)
  microCapMin = 0.10,
  microCapMax = 0.40,

  -- minimap icon (LibDBIcon)
  minimap = {
    hide = false,
  },

  -- Localization override. "auto" = use GetLocale().
  localeOverride = "auto",

  -- Midnight anchor system (overlay fades + cast success correlation)
  anchors = {
    enabled = true,
    fadeWindow = 0.25,
    successWindow = 0.40,
    castHistorySeconds = 2.0,
    maxEvents = 600,
    rules = {
      -- Populate per-spec after in-game verification.
      -- Key: overlaySpellID (from SPELL_ACTIVATION_OVERLAY_*), Value: rule table.
      -- [overlaySpellID] = { name="Proc", consume={spellID1, spellID2}, requireSucceeded=true }
    },
  },
}

-- ---------- public config ----------
function NS:GetConfig()
  local db = _G.GCDOptimizerDB
  if type(db) ~= "table" then
    db = {}
  end

  -- Hard reset SavedVariables on addon version change.
  -- This is intentional to avoid config drift when updating from old Curse builds.
  local prev = db.__addonVersion
  if prev ~= NS.VERSION then
    db = {}
  end

  db = DeepCopyDefaults(db, DEFAULTS)
  db.__addonVersion = NS.VERSION

  _G.GCDOptimizerDB = db
  NS.db = db
  return db
end


-- ---------- state ----------
NS.state = NS.state or {
  inSegment = false,
  segmentStart = 0,
  segmentEnd = 0,
  -- "Effective" end time used for final report: excludes post-last-action idle tail
  -- (dummy combat drops late). Populated at segment end.
  segmentEndEffective = 0,
  autoCombat = false, -- true if current segment started by combat autostart
}

-- ---------- segment lifecycle ----------
function NS:StartSegment(now)
  now = now or Now()
  if NS.state.inSegment then
    -- Prefer resetting on entering combat (user request):
    -- If a manual segment is running, restart it as a combat segment.
    if not NS.state.autoCombat then
      NS:ResetSegment(Now())
      NS.state.autoCombat = true
      NS:StartSegment(Now())
    end
    return
  end

  NS.state.inSegment = true
  NS.state.segmentStart = now
  NS.state.segmentEnd = 0
  NS.state.segmentEndEffective = 0
  -- autoCombat flag is set by caller (combat handler); default false for manual
  if NS.state.autoCombat == nil then NS.state.autoCombat = false end

  SafeCall(NS.GCDEstimator, "OnSegmentStart", now)

  -- Avoid cross-segment press de-dupe / window bleed.
  SafeCall(NS.PressTracker, "Reset")

  SafeCall(NS.Metrics, "OnSegmentStart", now)
  SafeCall(NS.Integrator, "OnSegmentStart", now)
  SafeCall(NS.GCDDetector, "OnSegmentStart", now)

  -- NEW
  SafeCall(NS.Failures, "OnSegmentStart", now)

  SafeCall(NS.HUD, "OnSegmentStart", now)
end

function NS:PauseSegment(now)
  now = now or Now()
  if not NS.state.inSegment then return end

  NS.state.inSegment = false
  NS.state.segmentEnd = now
  NS.state.segmentEndEffective = now

  SafeCall(NS.GCDEstimator, "OnSegmentEnd", now)

  SafeCall(NS.Metrics, "OnSegmentEnd", now)
  -- Propagate effective end (tail-cut) into shared state for Integrator/HUD.
  if NS.Metrics and NS.Metrics.segmentEndEffective then
    NS.state.segmentEndEffective = NS.Metrics.segmentEndEffective
  end
  SafeCall(NS.Integrator, "OnSegmentEnd", now)
  SafeCall(NS.GCDDetector, "OnSegmentEnd", now)
  SafeCall(NS.Anchors, "OnSegmentEnd", now)

  -- NEW
  SafeCall(NS.Failures, "OnSegmentEnd", now)

  SafeCall(NS.HUD, "OnSegmentEnd", now)
end

function NS:ResetSegment(now)
  now = now or Now()

  NS.state.inSegment = false
  NS.state.segmentStart = now
  NS.state.segmentEnd = now
  NS.state.segmentEndEffective = now
  NS.state.autoCombat = false
  SafeCall(NS.PressTracker, "Reset")

  SafeCall(NS.GCDEstimator, "Reset", now)

  SafeCall(NS.Metrics, "Reset", now)
  SafeCall(NS.Integrator, "Reset", now)
  SafeCall(NS.GCDDetector, "Reset", now)
  SafeCall(NS.Anchors, "Reset", now)

  -- NEW
  SafeCall(NS.Failures, "Reset", now)

  SafeCall(NS.HUD, "Update")
end

-- Reset counters and immediately continue the current segment (if running).
-- This matches the original "Reset" button semantics: clear stats without stopping tracking.
function NS:ResetAndContinue(now)
  now = now or Now()

  local wasRunning = NS.state.inSegment
  local wasAuto = NS.state.autoCombat

  NS:ResetSegment(now)

  if wasRunning then
    NS.state.autoCombat = wasAuto
    NS:StartSegment(now)
  end
end

-- Optional: modules can call these if they want to route via Core.
function NS:OnPress(kind, id)
  if NS.state.inSegment then
    SafeCall(NS.Metrics, "OnPress", Now(), kind, id)
  end
end

function NS:OnGCDStart(gcdStart, gcdDur)
  if NS.state.inSegment then
    -- Feed estimator with any observed duration (when readable) for calibration.
    SafeCall(NS.GCDEstimator, "OnGCDStart", gcdStart, gcdDur)

    SafeCall(NS.Metrics, "OnGCDStart", gcdStart, gcdDur)
    SafeCall(NS.HUD, "OnGCDStart")
  end
end

function NS:OnRateUpdate()
  SafeCall(NS.HUD, "OnRateUpdate")
end

-- ---------- init ----------
function NS:Init()
  if NS._inited then return end
  NS._inited = true

  local cfg = NS:GetConfig()

  -- NEW: init Failures tracker early
  SafeCall(NS.Failures, "Init")

  -- NEW: init Anchors (overlay fade + cast correlation)
  SafeCall(NS.Anchors, "Init")

  -- init other modules (safe even if module has no Init)
  SafeCall(NS.GCDEstimator, "Init")

  SafeCall(NS.Metrics, "Reset", Now())
  SafeCall(NS.Integrator, "Reset", Now())
  SafeCall(NS.GCDDetector, "Reset", Now())
  SafeCall(NS.Anchors, "Reset", Now())

  SafeCall(NS.HUD, "Init")
  SafeCall(NS.Options, "Init")
  SafeCall(NS.Minimap, "Init")

  -- Ensure clean baseline
  NS:ResetSegment(Now())

  -- Apply HUD visibility from config
  if NS.HUD and NS.HUD.frame then
    NS.HUD.frame:SetShown(cfg.showHUD)
  end
end

-- ---------- combat handlers ----------
function NS:OnCombatStart()
  local cfg = NS:GetConfig()
  if not cfg.autoStartCombat then return end
  if NS.state.inSegment then
    -- Prefer resetting on entering combat (user request):
    -- If a manual segment is running, restart it as a combat segment.
    if not NS.state.autoCombat then
      NS:ResetSegment(Now())
      NS.state.autoCombat = true
      NS:StartSegment(Now())
    end
    return
  end

  -- Mark this segment as combat-started so we can auto-stop it.
  NS.state.autoCombat = true
  NS:StartSegment(Now())
end

function NS:OnCombatEnd()
  local cfg = NS:GetConfig()
  if not cfg.autoStopCombat then return end
  if not NS.state.inSegment then return end

  -- Only auto-stop segments that were auto-started by combat.
  if NS.state.autoCombat then
    NS.state.autoCombat = false
    NS:PauseSegment(Now())
  end
end

-- ---------- events ----------
local EF = CreateFrame("Frame")
EF:RegisterEvent("ADDON_LOADED")
EF:RegisterEvent("PLAYER_LOGIN")
EF:RegisterEvent("PLAYER_REGEN_DISABLED") -- enter combat
EF:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leave combat

EF:SetScript("OnEvent", function(_, event, arg1, ...)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end
    NS:Init()
    return
  end

  if event == "PLAYER_LOGIN" then
    -- Ensure init in case ADDON_LOADED missed for any reason
    NS:Init()
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    NS:OnCombatStart()
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    NS:OnCombatEnd()
    return
  end
end)

-- ---------- slash commands ----------
SLASH_GCDOPT1 = "/gcdopt"
SlashCmdList.GCDOPT = function(msg)
  msg = (msg or ""):lower()
  local cfg = NS:GetConfig()

  if msg == "show" then
    cfg.showHUD = true
    if NS.HUD and NS.HUD.frame then NS.HUD.frame:Show() end
    if NS.HUD and NS.HUD.StartTicker then NS.HUD:StartTicker() end
    if NS.HUD and NS.HUD.Update then NS.HUD:Update(true) end
    return
  end

  if msg == "hide" then
    cfg.showHUD = false
    if NS.HUD and NS.HUD.StopTicker then NS.HUD:StopTicker() end
    if NS.HUD and NS.HUD.frame then NS.HUD.frame:Hide() end
    if NS.HUD and NS.HUD.detailsFrame then NS.HUD.detailsFrame:Hide() end
    return
  end

  if msg == "reset" then
	  NS:ResetAndContinue(Now())
    return
  end

  if msg == "start" then
    NS.state.autoCombat = false
    NS:StartSegment(Now())
    return
  end

  if msg == "stop" then
    NS.state.autoCombat = false
    NS:PauseSegment(Now())
    return
  end

  -- default: toggle HUD
  cfg.showHUD = not cfg.showHUD
  if NS.HUD and NS.HUD.frame then
    NS.HUD.frame:SetShown(cfg.showHUD)
  end
end
