-- GCDOptimizer_Integrator.lua
-- Observation-driven capacity estimate. Rendering never advances measurement
-- or queries game APIs. A bounded rate history supports delayed GCD timestamps;
-- an action checkpoint preserves the final tail cut even after history eviction.

local _, NS = ...
local U = NS.Util

NS.Integrator = NS.Integrator or {}
local I = NS.Integrator
local HISTORY_LIMIT = 256

local function Rate(duration, source)
  if (source == U.GCD_SOURCE_DIRECT or source == U.GCD_SOURCE_ESTIMATED)
    and U.IsFiniteNumber(duration) and duration > 0
  then
    return 1 / duration
  end
  return 0
end

function I:Reset()
  self.started = false
  self.segStart = 0
  self.lastT = 0
  self.lastG = 1.5
  self.lastSource = U.GCD_SOURCE_CACHED
  self.rate = 0
  self.totalIntervals = 0
  self.history = U.Deque:New()
  self.actionAt = nil
  self.actionIntervals = nil
  self.finalIntervals = nil
end

function I:OnSegmentStart(startTime)
  self:Reset()
  self.started = true
  self.segStart = startTime or GetTime()
  self.lastT = self.segStart
  self.history:PushBack({ t = self.segStart, total = 0, rate = 0 })
end

function I:ReanchorStart(startTime)
  if not U.IsFiniteNumber(startTime) or startTime <= 0 then return end
  local duration, source = self.lastG, self.lastSource
  self:OnSegmentStart(startTime)
  self:Observe(startTime, duration, source)
end

function I:ValueAt(timestamp)
  if timestamp <= self.segStart then return 0 end
  local history = self.history
  for index = history.tail, history.head, -1 do
    local span = history.data[index]
    if timestamp >= span.t then
      return span.total + (timestamp - span.t) * span.rate
    end
  end
  -- Outside the bounded correction history: do not extrapolate an old rate.
  return nil
end

function I:Observe(timestamp, duration, source)
  if not self.started or not U.IsFiniteNumber(timestamp) or timestamp < self.lastT then return end

  self.totalIntervals = self.totalIntervals + (timestamp - self.lastT) * self.rate
  self.lastT = timestamp
  local rate = Rate(duration, source)
  if rate ~= self.rate then
    local tail = self.history:Back()
    if tail and tail.t == timestamp then
      tail.rate = rate
    else
      self.history:PushBack({ t = timestamp, total = self.totalIntervals, rate = rate })
      while self.history:Size() > HISTORY_LIMIT do self.history:PopFront() end
    end
    self.rate = rate
  end
  if U.IsFiniteNumber(duration) and duration > 0 then self.lastG = duration end
  self.lastSource = source or U.GCD_SOURCE_CACHED
end

function I:CheckpointAction(timestamp)
  if not self.started or not U.IsFiniteNumber(timestamp) or timestamp <= 0 then return end
  if timestamp == self.actionAt then return end
  local total = self:ValueAt(timestamp)
  if total == nil then return end
  self.actionAt = timestamp
  self.actionIntervals = total
end

function I:OnSegmentEnd(endTime)
  if not self.started then return end
  local finish = NS.state and NS.state.segmentEndEffective or endTime or GetTime()
  local total
  if finish == self.actionAt then total = self.actionIntervals end
  if total == nil then total = self:ValueAt(finish) end
  self.finalIntervals = math.max(0, total or self.actionIntervals or 0)
  self.started = false
end

function I:GetCurrentPrediction()
  return self.lastG or 1.5, self.lastSource or U.GCD_SOURCE_CACHED
end

function I:GetPossibleFight(now)
  if self.finalIntervals ~= nil then return self.finalIntervals end
  if not self.started then return 0 end
  return math.max(0, self:ValueAt(now or GetTime()) or 0)
end
