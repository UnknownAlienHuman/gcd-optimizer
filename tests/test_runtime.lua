local ROOT = "./"

local failures = 0
local function check(condition, message)
  if not condition then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end

local function close(actual, expected, epsilon, message)
  check(type(actual) == "number" and math.abs(actual - expected) <= epsilon,
    message .. string.format(" (actual=%s expected=%s)", tostring(actual), tostring(expected)))
end

local now = 100
local spellQueueWindow = 400
function GetTime() return now end
function GetCVar(name) return name == "SpellQueueWindow" and tostring(spellQueueWindow) or "0" end
function GetNetStats() return 0, 0, 30, 40 end

local SECRET = {}
function canaccessallvalues(...)
  for index = 1, select("#", ...) do
    if select(index, ...) == SECRET then return false end
  end
  return true
end
function canaccesstable(value)
  assert(type(value) == "table", "canaccesstable received a non-table")
  return value ~= SECRET
end

local cooldown = { isActive = false, startTime = 0, duration = 0, modRate = 1 }
C_Spell = {}
function C_Spell.GetSpellCooldown() return cooldown end

local swing = 2.0
function UnitAttackSpeed() return swing, nil end

local registeredFrames = {}
function CreateFrame()
  local frame = { events = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:RegisterUnitEvent(event) self.events[event] = true end
  function frame:SetScript(kind, callback) self[kind] = callback end
  registeredFrames[#registeredFrames + 1] = frame
  return frame
end

local timers = {}
C_Timer = {}
function C_Timer.NewTicker(_, callback)
  local object = { callback = callback, cancelled = false }
  function object:Cancel() self.cancelled = true end
  return object
end
function C_Timer.NewTimer(_, callback)
  local object = { callback = callback, cancelled = false }
  function object:Cancel() self.cancelled = true end
  timers[#timers + 1] = object
  return object
end

local NS = {}
function NS:GetConfig()
  return {
    pollInterval = 0.05,
    statWindowN = 60,
    pressBufferSeconds = 8,
    pressBufferMax = 1200,
    dynamicMicroCap = true,
    microCap = 0.20,
    microCapMargin = 0.05,
    microCapMin = 0.10,
    microCapMax = 0.40,
    sysDelayMinSamples = 6,
    sysDelayLatencyFactor = 0.5,
    recommendMinSamples = 20,
    recommendLatencyFactor = 0.9,
    recommendMaxMs = 400,
    recommendStepMs = 5,
  }
end

assert(loadfile(ROOT .. "GCDOptimizer_Util.lua"))("GCDOptimizer", NS)
local U = NS.Util
check(U.CanAccessTable(nil) == false, "table gate rejects nil before canaccesstable")

-- Secret-aware direct observation and modRate normalization.
cooldown = { isActive = true, startTime = 10, duration = 1.5, modRate = 1.5 }
local status, startTime, duration = U.ReadGCDObservation()
check(status == U.GCD_STATUS_EXACT, "direct observation status")
close(startTime, 10, 1e-9, "direct start")
close(duration, 1.0, 1e-9, "modRate-normalized duration")

cooldown = { isActive = false, startTime = SECRET, duration = SECRET, modRate = SECRET }
status = U.ReadGCDObservation()
check(status == U.GCD_STATUS_INACTIVE, "NeverSecret activity can reject inactive GCD")

cooldown = { isActive = true, startTime = SECRET, duration = SECRET, modRate = SECRET }
status = U.ReadGCDObservation()
check(status == U.GCD_STATUS_ACTIVE_RESTRICTED, "restricted active GCD classification")

-- One-second profiles are calibrated from direct evidence, not a class table.
assert(loadfile(ROOT .. "GCDOptimizer_GCDEstimator.lua"))("GCDOptimizer", NS)
NS.GCDEstimator:Init()
swing = 2.0
cooldown = { isActive = true, startTime = 20, duration = 1.0, modRate = 1.0 }
local predicted, source = NS.GCDEstimator:GetPrediction()
close(predicted, 1.0, 1e-9, "direct one-second calibration")
check(source == U.GCD_SOURCE_DIRECT, "direct estimator source")

swing = 1.5
cooldown = { isActive = true, startTime = SECRET, duration = SECRET, modRate = SECRET }
predicted, source = NS.GCDEstimator:GetPrediction()
close(predicted, 0.75, 1e-9, "swing-ratio estimate")
check(source == U.GCD_SOURCE_ESTIMATED, "estimated source label")

-- Repeated reads of the same direct GCD must not pair a later swing speed with
-- the original GCD duration.
swing = 3.0
cooldown = { isActive = true, startTime = 20, duration = 1.0, modRate = 1.0 }
NS.GCDEstimator:GetPrediction()
close(NS.GCDEstimator.calibrationSwing, 2.0, 1e-9, "same-start poll does not recalibrate swing")

cooldown = { isActive = true, startTime = SECRET, duration = SECRET, modRate = SECRET }
NS.GCDEstimator:InvalidateCalibration("test")
predicted, source = NS.GCDEstimator:GetPrediction()
close(predicted, 1.0, 1e-9, "cached direct duration")
check(source == U.GCD_SOURCE_CACHED, "cached source label")

-- Exact attribution: zero/multiple candidates are not treated as exact input.
assert(loadfile(ROOT .. "GCDOptimizer_Metrics.lua"))("GCDOptimizer", NS)
local M = NS.Metrics
M:OnSegmentStart(0.1)
M:OnGCDStart(0.1, 1.0, U.GCD_SOURCE_DIRECT)
M:OnGCDStart(1.1, 1.0, U.GCD_SOURCE_DIRECT) -- no candidate
M:OnPress(1.95)
M:OnPress(2.00)
M:OnGCDStart(2.1, 1.0, U.GCD_SOURCE_DIRECT) -- ambiguous
M:OnPress(3.00)
M:OnGCDStart(3.1, 1.0, U.GCD_SOURCE_DIRECT) -- one queued candidate
M:OnGCDStart(4.1, 1.0, U.GCD_SOURCE_ESTIMATED) -- excluded

check(M:GetSecondsSinceLastPress(4.1) ~= nil, "known press yields an idle duration")

local counts = M:GetPressClassCounts()
check(counts.cycles == 3, "three exact-to-exact cycles")
check(counts.unobserved == 1, "zero candidate is unobserved")
check(counts.ambiguous == 1, "multiple candidates are ambiguous")
check(counts.queued == 1 and counts.late == 0, "single candidate is attributable")

local observations = M:GetObservationCounts()
check(observations.direct == 4, "direct start count")
check(observations.estimated == 1, "estimated start count")
check(observations.exactCycles == 3, "estimated boundary excluded from exact cycles")
check(observations.attributable == 1, "only one exact attributable cycle")

local _, recommendationInfo = M:RecommendSpellQueueWindow()
check(recommendationInfo.sampleN == 1, "SQW uses only exact unambiguous candidates")
check(recommendationInfo.lowSample == true, "SQW reports low sample")

M:OnSegmentStart(5)
check(M:GetSecondsSinceLastPress(7) == nil, "missing hook evidence is not player-idle proof")

-- An extreme queue window must not reuse the press that started the previous
-- GCD as evidence for the next one.
spellQueueWindow = 4000
M:OnSegmentStart(6)
M:OnPress(6)
M:OnGCDStart(6, 1.0, U.GCD_SOURCE_DIRECT)
M:OnGCDStart(7, 1.0, U.GCD_SOURCE_DIRECT)
counts = M:GetPressClassCounts()
check(counts.unobserved == 1 and counts.attributable == 0,
  "attribution never reaches into the previous GCD-start press")
spellQueueWindow = 400

-- A later direct observation upgrades, rather than duplicates, an estimate.
M:OnSegmentStart(10)
M:OnGCDStart(10, 1.0, U.GCD_SOURCE_DIRECT)
M:OnGCDStart(11, 1.0, U.GCD_SOURCE_ESTIMATED)
check(M:UpgradeLastGCD(11, 11.1, 1.0, U.GCD_SOURCE_DIRECT), "estimated start upgrade")
observations = M:GetObservationCounts()
check(observations.total == 2, "upgrade does not duplicate total starts")
check(observations.direct == 2 and observations.estimated == 0, "upgrade source counts")
check(observations.exactCycles == 1, "upgrade restores exact cycle")

-- Detector: inactive off-GCD success is rejected; restricted active success can
-- create an explicitly estimated start; later exact timing upgrades it.
assert(loadfile(ROOT .. "GCDOptimizer_GCDDetector.lua"))("GCDOptimizer", NS)
NS.state = { inSegment = true, segmentStart = 19, autoCombat = false }
local accepted = {}
local upgraded = {}
local refreshed = {}
function NS:OnGCDStart(startValue, durationValue, sourceValue)
  accepted[#accepted + 1] = { startValue, durationValue, sourceValue }
end
function NS:OnGCDUpgrade(oldValue, newValue, durationValue, sourceValue)
  upgraded[#upgraded + 1] = { oldValue, newValue, durationValue, sourceValue }
end
function NS:OnGCDRefresh(startValue, durationValue, sourceValue)
  refreshed[#refreshed + 1] = { startValue, durationValue, sourceValue }
end

NS.GCDDetector:Init()
NS.GCDDetector:OnSegmentStart()

cooldown = { isActive = false, startTime = SECRET, duration = SECRET, modRate = SECRET }
NS.GCDDetector:Observe("UNIT_SPELLCAST_SUCCEEDED")
NS.GCDDetector:ScheduleEstimatedFallback(20)
check(#accepted == 0, "off-GCD success does not create a GCD")

-- Recalibrate, then restrict numerical fields while activity remains true.
swing = 2.0
cooldown = { isActive = true, startTime = 19, duration = 1.0, modRate = 1.0 }
NS.GCDEstimator:GetPrediction()
cooldown = { isActive = true, startTime = SECRET, duration = SECRET, modRate = SECRET }
NS.GCDDetector:Observe("UNIT_SPELLCAST_SUCCEEDED")
NS.GCDDetector:ScheduleEstimatedFallback(20)
local timer = timers[#timers]
check(timer and not timer.cancelled, "estimated fallback timer scheduled")
timer.callback()
check(#accepted == 1 and accepted[1][3] == U.GCD_SOURCE_ESTIMATED, "restricted active event yields estimated start")

NS.GCDDetector:ScheduleEstimatedFallback(20.5)
timer = timers[#timers]
timer.callback()
check(#accepted == 1, "mid-GCD off-GCD success is cadence-rejected while activity stays continuous")

cooldown = { isActive = true, startTime = 20.1, duration = 1.0, modRate = 1.0 }
NS.GCDDetector:Observe("SPELL_UPDATE_COOLDOWN")
check(#accepted == 1, "direct observation upgrades instead of duplicating")
check(#upgraded == 1 and upgraded[1][4] == U.GCD_SOURCE_DIRECT, "estimate upgraded to direct")

cooldown = { isActive = true, startTime = 20.1, duration = 0.8, modRate = 1.0 }
NS.GCDDetector:Observe("SPELL_UPDATE_COOLDOWN")
check(#accepted == 1 and #refreshed == 1, "same-start duration refresh does not duplicate the cycle")
close(refreshed[1][2], 0.8, 1e-9, "same-start duration refresh value")
NS.GCDDetector:Observe("ticker")
check(#refreshed == 1, "unchanged direct polls do not spam duration refreshes")

-- A lower-quality same-cycle estimate cannot overwrite direct duration.
NS.GCDDetector:AcceptStart(20.12, 1.4, U.GCD_SOURCE_ESTIMATED)
close(NS.GCDDetector.lastCountedDuration, 0.8, 1e-9, "estimated timing cannot downgrade exact timing")

cooldown = { isActive = true, startTime = 29, duration = 0.8, modRate = 1.0 }
NS.GCDEstimator:GetPrediction()

-- Manual start inside a restricted active GCD must wait for a post-start
-- inactive transition before it can claim an estimated cycle.
local beforeManualPrime = #accepted
NS.state = { inSegment = true, segmentStart = 30, autoCombat = false }
cooldown = { isActive = true, startTime = SECRET, duration = SECRET, modRate = SECRET }
NS.GCDDetector:OnSegmentStart()
NS.GCDDetector:ScheduleEstimatedFallback(30.1)
timer = timers[#timers]
timer.callback()
check(#accepted == beforeManualPrime, "manual start does not claim an already-active restricted GCD")

cooldown = { isActive = false, startTime = SECRET, duration = SECRET, modRate = SECRET }
NS.GCDDetector:Observe("ticker")
cooldown = { isActive = true, startTime = SECRET, duration = SECRET, modRate = SECRET }
NS.GCDDetector:Observe("UNIT_SPELLCAST_SUCCEEDED")
NS.GCDDetector:ScheduleEstimatedFallback(31.0)
timer = timers[#timers]
timer.callback()
check(#accepted == beforeManualPrime + 1, "post-start inactive transition enables a new estimated cycle")

if failures > 0 then
  error(string.format("%d test(s) failed", failures))
end
print("runtime tests: PASS")
