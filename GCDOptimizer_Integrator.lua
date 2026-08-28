-- GCDOptimizer_Integrator.lua
-- Piecewise integration of the last ordinary GCD duration supplied by the
-- estimator. It never reads combat state directly.

local _, NS = ...

NS.Integrator = NS.Integrator or {}
local I = NS.Integrator

local function Now()
  return GetTime()
end

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
  self.totalIntervals = 0
  self.sampleMin = 0.30
  self._nextSampleAt = 0
end

function I:OnSegmentStart(startTime)
  self:Reset()
  self.started = true
  self.segStart = startTime or Now()
  self.lastT = self.segStart
  self.lastG = ComputePredictedGCD()
  self._nextSampleAt = self.segStart + self.sampleMin
end

-- Used only for the first auto-combat GCD when PLAYER_REGEN_DISABLED arrives
-- just after that GCD started. No integrated samples exist yet at this point.
function I:ReanchorStart(startTime)
  if type(startTime) ~= "number" or startTime <= 0 then return end
  self.started = true
  self.segStart = startTime
  self.lastT = startTime
  self.lastG = ComputePredictedGCD()
  self.totalIntervals = 0
  self._nextSampleAt = startTime + (self.sampleMin or 0.30)
end

function I:OnSegmentEnd()
  -- The final end point is read from NS.state by GetPossibleFight().
end

function I:_SampleAt(timestamp)
  if not self.started or timestamp <= self.lastT then return end

  local elapsed = timestamp - self.lastT
  if elapsed > 0 and self.lastG > 0 then
    self.totalIntervals = self.totalIntervals + (elapsed / self.lastG)
  end

  self.lastT = timestamp
  self.lastG = ComputePredictedGCD()
end

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

function I:GetPossibleFight(now)
  if not (NS.state and NS.state.segmentStart and NS.state.segmentStart > 0) then
    return 0
  end

  local endTime = GetEndTime(now)
  if endTime <= NS.state.segmentStart then return 0 end

  if NS.state.inSegment then
    self:MaybeSample(endTime)
  end
  if not self.started then
    self:OnSegmentStart(NS.state.segmentStart)
  end

  local total = self.totalIntervals or 0
  if self.lastT and endTime > self.lastT and self.lastG and self.lastG > 0 then
    total = total + ((endTime - self.lastT) / self.lastG)
  end
  return math.max(0, total)
end

function I:GetPossibleBetween(startTime, endTime)
  if not startTime or not endTime or endTime <= startTime then return 0 end
  local duration = ComputePredictedGCD()
  if duration <= 0 then return 0 end
  return (endTime - startTime) / duration
end
