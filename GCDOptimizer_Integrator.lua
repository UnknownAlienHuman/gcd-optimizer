-- GCDOptimizer_Integrator.lua
-- Computes predicted GCD over time and integrates "possible GCD intervals" piecewise.
-- Goal: avoid undercounting possible GCD when haste/SQW changes during fight.

local _, NS = ...
local U = NS.Util

NS.Integrator = NS.Integrator or {}
local I = NS.Integrator

local function Now() return GetTime() end

local function Clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

-- Predicted GCD model:
-- In Midnight, UnitSpellHaste / cooldown fields can become Secret in combat.
-- Always ask GCDEstimator for a safe numeric prediction.
local function ComputePredictedGCD()
  if NS.GCDEstimator and NS.GCDEstimator.GetPredictedGCD then
    return NS.GCDEstimator:GetPredictedGCD()
  end
  return 1.5
end

function I:Reset()
  self.started = false
  self.segStart = 0

  self.lastT = 0
  self.lastG = 1.5
  self.totalIntervals = 0 -- integral of dt/g over [segStart, lastT]

  self.sampleMin = 0.30   -- seconds; sampling granularity for piecewise integration
  self._nextSampleAt = 0
end

function I:OnSegmentStart(t0)
  self:Reset()
  self.started = true
  self.segStart = t0 or Now()

  local g = ComputePredictedGCD()
  self.lastT = self.segStart
  self.lastG = g
  self.totalIntervals = 0
  self._nextSampleAt = self.segStart + self.sampleMin
end

function I:OnSegmentEnd(t1)
  -- no-op; end time is read from NS.state.segmentEndEffective/segmentEnd
end

-- Internal sampling: add one piece [lastT, tNow] using lastG, then update lastG.
function I:_SampleAt(tNow)
  if not self.started then return end
  if tNow <= self.lastT then return end

  -- integrate with lastG
  local dt = tNow - self.lastT
  if dt > 0 and self.lastG > 0 then
    self.totalIntervals = self.totalIntervals + (dt / self.lastG)
  end

  -- update
  self.lastT = tNow
  self.lastG = ComputePredictedGCD()
end

-- Called frequently by HUD; only records samples when segment active and time reached.
function I:MaybeSample(now)
  if not (NS.state and NS.state.inSegment) then return end
  now = now or Now()
  if not self.started then
    self:OnSegmentStart(NS.state.segmentStart or now)
  end
  if now < (self._nextSampleAt or 0) then return end

  self:_SampleAt(now)
  self._nextSampleAt = now + self.sampleMin
end

function I:GetCurrentPredictedGCD()
  local now = Now()
  self:MaybeSample(now)
  return ComputePredictedGCD()
end

local function GetEndTime(now)
  if NS.state and NS.state.inSegment then
    return now or Now()
  end
  if NS.state and NS.state.segmentEndEffective and NS.state.segmentEndEffective > 0 then
    return NS.state.segmentEndEffective
  end
  if NS.state and NS.state.segmentEnd and NS.state.segmentEnd > 0 then
    return NS.state.segmentEnd
  end
  return now or Now()
end

-- Returns float: possible INTERVALS (not starts) between segment start and end.
-- HUD converts to starts as floor(intervals + 1).
function I:GetPossibleFight(now)
  if not (NS.state and NS.state.segmentStart and NS.state.segmentStart > 0) then
    return 0
  end

  local tEnd = GetEndTime(now)
  if tEnd <= (NS.state.segmentStart or 0) then return 0 end

  -- If segment active, keep sampling up to now (piecewise integration).
  if NS.state.inSegment then
    self:MaybeSample(tEnd)
  end

  -- Ensure we have baseline.
  if not self.started then
    self:OnSegmentStart(NS.state.segmentStart)
  end

  -- totalIntervals covers [segStart, lastT]. If end is beyond lastT (pause/end), extend with lastG.
  local total = self.totalIntervals or 0
  if self.lastT and tEnd > self.lastT and self.lastG and self.lastG > 0 then
    total = total + ((tEnd - self.lastT) / self.lastG)
  end
  if total < 0 then total = 0 end
  return total
end

-- For tails/short ranges; approximate using predicted GCD at call time.
-- (We keep it simple because callers use it for near-now windows.)
function I:GetPossibleBetween(tA, tB, now)
  if not tA or not tB or tB <= tA then return 0 end
  local g = ComputePredictedGCD()
  if g <= 0 then return 0 end
  return (tB - tA) / g
end
