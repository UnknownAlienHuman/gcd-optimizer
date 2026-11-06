-- GCDOptimizer_Metrics.lua
-- Source-aware cadence and input analytics. Estimated starts remain useful for
-- approximate cadence, but only exact-to-exact cycles with one unambiguous
-- local press may feed latency and SpellQueueWindow recommendations.

local _, NS = ...
local U = NS.Util

NS.Metrics = NS.Metrics or {}
local M = NS.Metrics

local function Now()
  return GetTime()
end

local function DequeToArray(deque)
  local values = {}
  if not deque then return values end
  for value in deque:Iter() do values[#values + 1] = value end
  return values
end

local function PushLimited(deque, value, maximum)
  deque:PushBack(value)
  while deque:Size() > maximum do deque:PopFront() end
end

local function ClearArray(values)
  for index = #values, 1, -1 do values[index] = nil end
end

local function SafeGetCVarNumber(name, fallback)
  local value = GetCVar(name)
  local number = tonumber(value)
  if not number then return fallback end
  return number
end

local function GetDynamicMicroCap(config)
  local queueWindow = SafeGetCVarNumber("SpellQueueWindow", 400) / 1000
  local margin = config.microCapMargin
  if margin == nil then margin = 0.05 end
  local minimum = config.microCapMin
  if minimum == nil then minimum = 0.10 end
  local maximum = config.microCapMax
  if maximum == nil then maximum = 0.40 end
  return U.Clamp(queueWindow + margin, minimum, maximum)
end

local function ValidTiming(value)
  return U.IsFiniteNumber(value) and value > 0
end

local function PercentileSorted(values, percentile)
  local count = #values
  if count == 0 then return 0 end
  local index = math.floor(U.Clamp(percentile, 0, 1) * (count - 1) + 1)
  return values[index] or 0
end

local function MedianSorted(values)
  local count = #values
  if count == 0 then return 0 end
  local middle = math.floor((count + 1) / 2)
  if (count % 2) == 1 then return values[middle] or 0 end
  return ((values[middle] or 0) + (values[middle + 1] or 0)) / 2
end

local function EstimateSystemDelaySec(self, config)
  local samples = DequeToArray(self.startDelayQueued)
  if #samples >= (config.sysDelayMinSamples or 6) then
    table.sort(samples)
    local median = MedianSorted(samples)
    if median > 0 and median < 1 then
      return median
    end
  end

  local _, _, home, world = GetNetStats()
  local latency = 0
  if home and world then
    latency = math.max(tonumber(home) or 0, tonumber(world) or 0)
  else
    latency = tonumber(world) or tonumber(home) or 0
  end

  local factor = config.sysDelayLatencyFactor
  if factor == nil then factor = 0.50 end
  local estimate = U.Clamp((latency * factor) / 1000, 0.01, 0.30)
  return estimate
end

local function CountPresses(self, startTime, readyTime, endTime)
  local total, queued, late = 0, 0, 0
  local onlyPress = nil
  for press in self.pressQueue:Iter() do
    local timestamp = press.t
    if timestamp >= startTime and timestamp <= endTime then
      total = total + 1
      onlyPress = press
      if timestamp <= readyTime then queued = queued + 1 else late = late + 1 end
    end
  end
  return total, queued, late, onlyPress
end

local function HasPressBetween(self, startTime, endTime)
  for press in self.pressQueue:Iter() do
    if press.t >= startTime and press.t <= endTime then return true end
  end
  return false
end

function M:Reset()
  self.inSegment = false
  self.segmentStart = nil
  self.segmentEnd = nil
  self.segmentEndEffective = nil

  self.actualFight = 0
  self.directStarts = 0
  self.estimatedStarts = 0
  self.ineligibleCycles = 0
  self.continuityBroken = false
  self.upgradePreviousEligible = false

  self.lastGCDStart = nil
  self.lastGCDDur = nil
  self.lastGCDSource = nil
  self.lastReadyTime = nil
  self.lastPressAt = nil

  self.upgradePreviousStart = nil
  self.upgradePreviousDuration = nil
  self.upgradePreviousSource = nil

  self.wastedGCD = 0

  self.gapFull = U.Deque:New()
  self.queueLead = U.Deque:New()
  self.startDelayQueued = U.Deque:New()
  self.latePress = U.Deque:New()
  self.cycleData = U.Deque:New()
  self.cycleLog = U.Deque:New()
  self.pressQueue = U.Deque:New()

  self.cycleN = 0
  self.queuedN = 0
  self.lateN = 0
  self.noneN = 0
  self.ambiguousN = 0
  self.attributableN = 0
  self.queueCovN = 0
  self.afkGapN = 0
  self.afkGapPressN = 0
end

function M:OnSegmentStart(startTime)
  self:Reset()
  self.inSegment = true
  self.segmentStart = startTime
end

function M:GetLastActionTime()
  return math.max(self.lastGCDStart or 0, self.lastPressAt or 0)
end

function M:BreakContinuity()
  if not self.inSegment or self.continuityBroken then return end
  self.continuityBroken = true
  self.upgradePreviousEligible = false
  self.pressQueue = U.Deque:New()
  -- Keep segment totals, but a recommendation must be supported by fresh
  -- attributable cycles after the observation boundary.
  self.cycleData = U.Deque:New()
end

function M:OnSegmentEnd(endTime)
  self.inSegment = false
  self.segmentEnd = endTime

  local effectiveEnd = endTime
  local lastAction = self:GetLastActionTime()
  if lastAction > 0 and effectiveEnd > lastAction then effectiveEnd = lastAction end
  if self.segmentStart and effectiveEnd < self.segmentStart then effectiveEnd = self.segmentStart end
  self.segmentEndEffective = effectiveEnd
end

function M:GetEffectiveEnd(now)
  if self.inSegment then return now or Now() end
  return self.segmentEndEffective or self.segmentEnd or now or Now()
end

function M:ReanchorStart(startTime)
  self.segmentStart = startTime
end

function M:OnPress(timestamp)
  if not self.inSegment then return end

  local config = NS:GetConfig()
  local keepSeconds = config.pressBufferSeconds or 8.0
  local maximum = config.pressBufferMax or 1200

  self.pressQueue:PushBack({ t = timestamp })
  self.lastPressAt = timestamp
  self.pressQueue:PopFrontWhile(function(press)
    return press.t < (timestamp - keepSeconds)
  end)
  while self.pressQueue:Size() > maximum do self.pressQueue:PopFront() end
end

function M:AnalyzeExactCycle(previousStart, previousDuration, currentStart)
  if not (ValidTiming(previousStart) and ValidTiming(previousDuration) and ValidTiming(currentStart)) then return end

  local delta = currentStart - previousStart
  if delta <= 0 or delta >= 10 then return end

  local config = NS:GetConfig()
  local statisticLimit = config.statWindowN or 60
  self.cycleN = self.cycleN + 1

  local ready = previousStart + previousDuration
  local rawGap = math.max(0, currentStart - ready)
  local systemDelay = EstimateSystemDelaySec(self, config)
  local delay = math.max(0, rawGap - systemDelay)
  PushLimited(self.gapFull, delay, statisticLimit)

  local cap = config.dynamicMicroCap == false
    and (config.microCap or 0.20)
    or GetDynamicMicroCap(config)
  local micro = math.min(delay, cap)
  local afk = math.max(0, delay - micro)
  self.wastedGCD = self.wastedGCD + (micro / previousDuration)

  local queueWindow = math.max(0, SafeGetCVarNumber("SpellQueueWindow", 400) / 1000)
  -- Do not let an oversized CVar reach into the previous action that started
  -- this GCD. The next-action attribution window begins strictly after the
  -- previous start, even when a user or external addon sets an extreme value.
  local attributionStart = math.max(previousStart + 0.001, ready - queueWindow)
  local candidateCount, queuedCount, _, onlyPress = CountPresses(
    self,
    attributionStart,
    ready,
    currentStart
  )

  local queueCovered = queuedCount > 0
  if queueCovered then self.queueCovN = self.queueCovN + 1 end

  local queued = false
  local late = false
  local lateDelay = 0
  local queueDelay = nil

  if candidateCount == 0 then
    self.noneN = self.noneN + 1
  elseif candidateCount > 1 then
    self.ambiguousN = self.ambiguousN + 1
  else
    self.attributableN = self.attributableN + 1
    if onlyPress.t <= ready then
      queued = true
      self.queuedN = self.queuedN + 1
      local lead = math.max(0, ready - onlyPress.t)
      queueDelay = rawGap
      PushLimited(self.queueLead, lead, statisticLimit)
      PushLimited(self.startDelayQueued, rawGap, statisticLimit)
    else
      late = true
      self.lateN = self.lateN + 1
      lateDelay = math.max(0, onlyPress.t - ready)
      PushLimited(self.latePress, lateDelay, statisticLimit)
    end

    PushLimited(self.cycleData, {
      ready = ready,
      start = currentStart,
      press = onlyPress.t,
    }, statisticLimit)
  end

  local isAfkGap = delay > (cap + 1e-6)
  local afkPress = false
  if isAfkGap then
    afkPress = HasPressBetween(self, ready + cap, currentStart)
    self.afkGapN = self.afkGapN + 1
    if afkPress then self.afkGapPressN = self.afkGapPressN + 1 end
  end

  PushLimited(self.cycleLog, {
    t = currentStart,
    delay = delay,
    afk = afk,
    qCov = queueCovered,
    queued = queued,
    late = late,
    lateDelay = lateDelay,
    qDelay = queueDelay,
    afkGap = isAfkGap,
    afkPress = afkPress,
  }, 600)
end

function M:OnGCDStart(startTime, duration, source)
  if not self.inSegment then return end
  if not (ValidTiming(startTime) and ValidTiming(duration)) then return end
  if source ~= U.GCD_SOURCE_DIRECT and source ~= U.GCD_SOURCE_ESTIMATED then return end

  local previousStart = self.lastGCDStart
  local previousDuration = self.lastGCDDur
  local previousSource = self.lastGCDSource

  self.actualFight = self.actualFight + 1
  if source == U.GCD_SOURCE_DIRECT then
    self.directStarts = self.directStarts + 1
  else
    self.estimatedStarts = self.estimatedStarts + 1
  end
  self.upgradePreviousStart = previousStart
  self.upgradePreviousDuration = previousDuration
  self.upgradePreviousSource = previousSource
  self.upgradePreviousEligible = not self.continuityBroken

  if self.continuityBroken then
    self.pressQueue = U.Deque:New()
  end
  if previousStart then
    if not self.continuityBroken
      and previousSource == U.GCD_SOURCE_DIRECT and source == U.GCD_SOURCE_DIRECT
    then
      self:AnalyzeExactCycle(previousStart, previousDuration, startTime)
    else
      self.ineligibleCycles = self.ineligibleCycles + 1
    end
  end

  self.lastGCDStart = startTime
  self.lastGCDDur = duration
  self.lastGCDSource = source
  self.lastReadyTime = startTime + duration
  self.continuityBroken = false
end

function M:RefreshLastGCD(startTime, duration, source)
  if source ~= U.GCD_SOURCE_DIRECT then return false end
  if self.lastGCDSource ~= U.GCD_SOURCE_DIRECT then return false end
  if not (ValidTiming(startTime) and ValidTiming(duration)) then return false end
  if math.abs((self.lastGCDStart or 0) - startTime) > 0.05 then return false end

  self.lastGCDDur = duration
  self.lastReadyTime = self.lastGCDStart + duration
  return true
end

function M:UpgradeLastGCD(oldStart, newStart, duration, source)
  if source ~= U.GCD_SOURCE_DIRECT then return false end
  if self.lastGCDSource ~= U.GCD_SOURCE_ESTIMATED then return false end
  if not (ValidTiming(oldStart) and ValidTiming(newStart) and ValidTiming(duration)) then return false end
  if math.abs((self.lastGCDStart or 0) - oldStart) > 0.05 then return false end

  self.estimatedStarts = math.max(0, self.estimatedStarts - 1)
  self.directStarts = self.directStarts + 1

  self.lastGCDStart = newStart
  self.lastGCDDur = duration
  self.lastGCDSource = source
  self.lastReadyTime = newStart + duration

  if self.upgradePreviousEligible and not self.continuityBroken
    and self.upgradePreviousStart and self.upgradePreviousSource == U.GCD_SOURCE_DIRECT
  then
    self.ineligibleCycles = math.max(0, self.ineligibleCycles - 1)
    self:AnalyzeExactCycle(
      self.upgradePreviousStart,
      self.upgradePreviousDuration,
      newStart
    )
  end
  return true
end

function M:ComputeContext(windowSeconds, now, cutoffEnd)
  now = now or Now()
  local endTime = cutoffEnd or self:GetEffectiveEnd(now)
  local segmentStart = self.segmentStart or endTime
  local startTime = segmentStart
  if windowSeconds and windowSeconds > 0 then
    startTime = math.max(segmentStart, endTime - windowSeconds)
  end

  local cycles, queued, late, queueCoverage = 0, 0, 0, 0
  local afkTime, afkGapCount, afkPressCount = 0, 0, 0

  self._contextGaps = self._contextGaps or {}
  self._contextLate = self._contextLate or {}
  self._contextQueueDelay = self._contextQueueDelay or {}
  local gaps = self._contextGaps
  local lateDelays = self._contextLate
  local queueDelays = self._contextQueueDelay
  ClearArray(gaps)
  ClearArray(lateDelays)
  ClearArray(queueDelays)

  for cycle in self.cycleLog:Iter() do
    if cycle.t >= startTime and cycle.t <= endTime then
      cycles = cycles + 1
      afkTime = afkTime + (cycle.afk or 0)
      if cycle.queued then queued = queued + 1 end
      if cycle.late then late = late + 1 end
      if cycle.qCov then queueCoverage = queueCoverage + 1 end
      if cycle.afkGap then afkGapCount = afkGapCount + 1 end
      if cycle.afkPress then afkPressCount = afkPressCount + 1 end

      gaps[#gaps + 1] = cycle.delay or 0
      if cycle.late then lateDelays[#lateDelays + 1] = cycle.lateDelay or 0 end
      if cycle.qDelay then queueDelays[#queueDelays + 1] = cycle.qDelay end
    end
  end

  if #gaps > 1 then table.sort(gaps) end
  if #lateDelays > 1 then table.sort(lateDelays) end
  if #queueDelays > 1 then table.sort(queueDelays) end

  local output = self._contextOutput or {}
  self._contextOutput = output
  output.gapP90Sec = PercentileSorted(gaps, 0.90)
  output.qHit = cycles > 0 and (queued / cycles) or 0
  output.qCov = cycles > 0 and (queueCoverage / cycles) or 0
  output.lateShare = cycles > 0 and (late / cycles) or 0
  output.lateP90Ms = PercentileSorted(lateDelays, 0.90) * 1000
  output.qDelayP90Ms = PercentileSorted(queueDelays, 0.90) * 1000
  output.afkTime = afkTime
  output.afkDen = afkGapCount
  output.afkPressPct = afkGapCount > 0 and (afkPressCount / afkGapCount) or 0
  return output
end

function M:GetSecondsSinceLastPress(now)
  if not self.lastPressAt then return nil end
  return math.max(0, (now or Now()) - self.lastPressAt)
end

function M:GetFightDuration(now)
  if not self.segmentStart then return 0 end
  if self.inSegment then return (now or Now()) - self.segmentStart end
  local finish = self.segmentEndEffective or self.segmentEnd
  return finish and math.max(0, finish - self.segmentStart) or 0
end

function M:GetActualFight() return self.actualFight or 0 end

function M:GetWastedGCD() return self.wastedGCD or 0 end

function M:GetCurrentGap(atTime)
  if self.continuityBroken or not self.lastReadyTime then return 0 end
  return math.max(0, (atTime or Now()) - self.lastReadyTime)
end

local function StatsFromDeque(deque)
  local values = DequeToArray(deque)
  local count = #values
  if count == 0 then return { mean = 0, median = 0, p90 = 0, n = 0 } end

  local total = 0
  for index = 1, count do total = total + values[index] end
  if count > 1 then table.sort(values) end
  return {
    mean = total / count,
    median = MedianSorted(values),
    p90 = PercentileSorted(values, 0.90),
    n = count,
  }
end

function M:GetGapStatsFull() return StatsFromDeque(self.gapFull) end
function M:GetQueueLeadStats() return StatsFromDeque(self.queueLead) end
function M:GetStartDelayQueuedStats() return StatsFromDeque(self.startDelayQueued) end
function M:GetLatePressStats() return StatsFromDeque(self.latePress) end

function M:GetPressClassCounts()
  return {
    cycles = self.cycleN or 0,
    queued = self.queuedN or 0,
    late = self.lateN or 0,
    none = self.noneN or 0,
    unobserved = self.noneN or 0,
    ambiguous = self.ambiguousN or 0,
    attributable = self.attributableN or 0,
  }
end

function M:GetObservationCounts()
  return {
    total = self.actualFight or 0,
    direct = self.directStarts or 0,
    estimated = self.estimatedStarts or 0,
    exactCycles = self.cycleN or 0,
    ineligibleCycles = self.ineligibleCycles or 0,
    attributable = self.attributableN or 0,
    ambiguous = self.ambiguousN or 0,
    unobserved = self.noneN or 0,
  }
end

function M:GetQueueCoverageShare()
  local cycles = self.cycleN or 0
  local count = self.queueCovN or 0
  return count, cycles, cycles > 0 and (count / cycles) or 0
end


function M:GetAmbiguousShare()
  local cycles = self.cycleN or 0
  local count = self.ambiguousN or 0
  return count, cycles, cycles > 0 and (count / cycles) or 0
end

function M:GetAFKPressShare()
  local denominator = self.afkGapN or 0
  local count = self.afkGapPressN or 0
  return count, denominator, denominator > 0 and (count / denominator) or 0
end


function M:RecommendSpellQueueWindow()
  local config = NS:GetConfig()
  local cycles = DequeToArray(self.cycleData)
  local count = #cycles
  local diagnostic = {
    sampleN = count,
    eligibleN = count,
    exactCycles = self.cycleN or 0,
  }

  local _, _, ambiguousShare = self:GetAmbiguousShare()
  diagnostic.ambiguous = ambiguousShare
  diagnostic.multi = ambiguousShare

  local _, _, home, world = GetNetStats()
  local latency = tonumber(world) or tonumber(home) or 0
  if home and world then latency = math.max(home, world) end
  diagnostic.latencyMs = latency

  local minimumSamples = config.recommendMinSamples or 20
  if count < minimumSamples then
    diagnostic.lowSample = true
    diagnostic.coverage = 0
    diagnostic.noQueue = 1
    diagnostic.recommendedMs = SafeGetCVarNumber("SpellQueueWindow", 400)
    return diagnostic.recommendedMs, diagnostic
  end

  local minimum = math.floor(math.max(50, latency * (config.recommendLatencyFactor or 0.9)))
  local maximum = config.recommendMaxMs or 400
  local step = config.recommendStepMs or 5
  if minimum > maximum then minimum = maximum end

  local bestWindow, bestScore, bestCoverage = nil, -math.huge, 0
  for windowMs = minimum, maximum, step do
    local window = windowMs / 1000
    local covered = 0
    for index = 1, count do
      local cycle = cycles[index]
      if cycle.press >= (cycle.ready - window) and cycle.press <= cycle.ready then
        covered = covered + 1
      end
    end
    local coverage = count > 0 and (covered / count) or 0
    local score = coverage - (windowMs / 10000)
    if score > bestScore then
      bestWindow = windowMs
      bestScore = score
      bestCoverage = coverage
    end
  end

  if not bestWindow then bestWindow = math.min(400, maximum) end

  local leads = DequeToArray(self.queueLead)
  table.sort(leads)
  local medianLeadMs = 0
  if #leads > 0 then
    medianLeadMs = leads[math.floor((#leads + 1) / 2)] * 1000
  end
  local buffer = config.recommendLeadBufferMs
  if buffer == nil then buffer = math.floor(math.max(20, math.min(80, medianLeadMs))) end

  local recommendation = math.max(bestWindow, math.floor(latency + buffer))
  recommendation = U.Clamp(recommendation, 0, maximum)

  diagnostic.bestScore = bestScore
  diagnostic.coverage = bestCoverage
  diagnostic.noQueue = 1 - bestCoverage
  diagnostic.medianLeadMs = medianLeadMs
  diagnostic.extraMs = buffer
  diagnostic.recommendedMs = recommendation
  return recommendation, diagnostic
end
