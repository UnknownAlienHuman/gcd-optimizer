-- GCDOptimizer_GCDEstimator.lua
-- Retail 12.1 GCD duration cache with a strict Secret-value boundary.
--
-- The GCD dummy spell (61304) is authoritative whenever its cooldown is
-- accessible. When it is not, the estimator returns the last ordinary duration
-- observed in this session instead of deriving combat state from another API.

local _, NS = ...
local U = NS.Util

NS.GCDEstimator = NS.GCDEstimator or {}
local E = NS.GCDEstimator

local DEFAULT_GCD = 1.5
local MIN_GCD = 0.75
local MAX_GCD = 1.5

local function AcceptDuration(self, duration, source)
  if not U.CanAccessValues(duration) then return false end
  if type(duration) ~= "number" or duration <= 0 then return false end

  self.lastPred = U.Clamp(duration, MIN_GCD, MAX_GCD)
  self.source = source or "observed"
  self.sampleCount = (self.sampleCount or 0) + 1
  self.hasObserved = true
  self.lastSampleAt = GetTime()
  return true
end

function E:Init()
  if self._inited then return end
  self._inited = true
  self.lastPred = DEFAULT_GCD
  self.source = "fallback"
  self.sampleCount = 0
  self.hasObserved = false
  self.lastSampleAt = 0
end

function E:Reset()
  local carry = self.lastPred
  if type(carry) ~= "number" or carry <= 0 then
    carry = DEFAULT_GCD
  end

  self.lastPred = U.Clamp(carry, MIN_GCD, MAX_GCD)
  self.source = self.hasObserved and "session-cache" or "fallback"
  self.sampleCount = 0
  self.lastSampleAt = 0
end

function E:OnSegmentStart()
  local _, duration = U.ReadGCDCooldown()
  if duration then
    AcceptDuration(self, duration, "cooldown")
  end
end

function E:OnSegmentEnd()
  -- Keep the last ordinary duration as a session fallback.
end

function E:OnGCDStart(_, observedDuration)
  AcceptDuration(self, observedDuration, "cooldown")
end

-- Kept as a compatibility no-op for callers from older builds. A successful
-- cast is not sufficient evidence that the spell triggered the global cooldown.
function E:OnPlayerCastSuccess()
end

function E:GetPredictedGCD()
  local _, duration = U.ReadGCDCooldown()
  if duration then
    AcceptDuration(self, duration, "cooldown")
  end
  return self.lastPred or DEFAULT_GCD
end

function E:DebugSnapshot()
  return {
    lastPred = self.lastPred or DEFAULT_GCD,
    source = self.source or "fallback",
    sampleCount = self.sampleCount or 0,
    lastSampleAt = self.lastSampleAt or 0,
  }
end
