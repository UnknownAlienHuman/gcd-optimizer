-- GCDOptimizer_Integrator.lua
-- Piecewise integration of usable exact/estimated GCD durations. Cached or
-- default low-confidence values are display-only and never create possible-GCD
-- claims.

local _, NS = ...
local U = NS.Util

NS.Integrator = NS.Integrator or {}
local I = NS.Integrator

local function Now()
  return GetTime()
end

local function Prediction()
  if NS.GCDEstimator and NS.GCDEstimator.GetPrediction then
    return NS.GCDEstimator:GetPrediction()
  end
  return 1.5, U.GCD_SOURCE_CACHED
end

local function IsIntegrable(source)
  return source == U.GCD_SOURCE_DIRECT or source == U.GCD_SOURCE_ESTIMATED
end

function I:Reset()
  self.started = false
  self.segStart = 0
  self.lastT = 0
  self.lastG = 0
  self.lastSource = U.GCD_SOURCE_CACHED
  self.totalIntervals = 0
  self.sampleMin = 0.30
  self.nextSampleAt = 0
end

function I:OnSegmentStart(startTime)
  self:Reset()
  self.started = true
  self.segStart = startTime or Now()
  self.lastT = self.segStart
  self.lastG, self.lastSource = Prediction()
  self.nextSampleAt = self.segStart + self.sampleMin
end

function I:ReanchorStart(startTime)
  if not U.IsFiniteNumber(startTime) or startTime <= 0 then return end
  self.started = true
  self.segStart = startTime
  self.lastT = startTime
  self.lastG, self.lastSource = Prediction()
  self.totalIntervals = 0
  self.nextSampleAt = startTime + self.sampleMin
end

function I:OnSegmentEnd()
end

function I:SampleAt(timestamp)
  if not self.started or timestamp <= self.lastT then return end

  local elapsed = timestamp - self.lastT
  if elapsed > 0 and self.lastG > 0 and IsIntegrable(self.lastSource) then
    self.totalIntervals = self.totalIntervals + (elapsed / self.lastG)
  end

  self.lastT = timestamp
  self.lastG, self.lastSource = Prediction()
end

function I:MaybeSample(now)
  if not (NS.state and NS.state.inSegment) then return end
  now = now or Now()
  if not self.started then self:OnSegmentStart(NS.state.segmentStart or now) end
  if now < (self.nextSampleAt or 0) then return end

  self:SampleAt(now)
  self.nextSampleAt = now + self.sampleMin
end

function I:GetCurrentPrediction()
  local now = Now()
  self:MaybeSample(now)
  local duration, source = Prediction()
  return duration, source
end

local function EndTime(now)
  if NS.state and NS.state.inSegment then return now or Now() end
  if NS.state and NS.state.segmentEndEffective and NS.state.segmentEndEffective > 0 then
    return NS.state.segmentEndEffective
  end
  if NS.state and NS.state.segmentEnd and NS.state.segmentEnd > 0 then
    return NS.state.segmentEnd
  end
  return now or Now()
end

function I:GetPossibleFight(now)
  if not (NS.state and NS.state.segmentStart and NS.state.segmentStart > 0) then return 0 end

  local finish = EndTime(now)
  if finish <= NS.state.segmentStart then return 0 end
  if NS.state.inSegment then self:MaybeSample(finish) end
  if not self.started then self:OnSegmentStart(NS.state.segmentStart) end

  local total = self.totalIntervals or 0
  if self.lastT and finish > self.lastT and self.lastG > 0 and IsIntegrable(self.lastSource) then
    total = total + ((finish - self.lastT) / self.lastG)
  end
  return math.max(0, total)
end

