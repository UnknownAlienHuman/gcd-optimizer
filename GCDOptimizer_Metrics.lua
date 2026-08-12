-- GCDOptimizer_Metrics.lua
-- Metrics v7: REAL presses + queue/late + server delay hints
-- Removes: PDG
-- Adds:
--   QC%   (Queue Coverage): any press in [ready-SQW, ready] regardless of late
--   AFKp% (AFK Press): among cycles with gap > MicroCap, any press in [ready+MicroCap, start]
-- Keeps:
--   SDq>0%: share of queued cycles with StartDelay(q) > epsilon

local _, NS = ...
local U = NS.Util

NS.Metrics = NS.Metrics or {}
local M = NS.Metrics

local function DequeToArray(dq)
  local arr = {}
  for v in dq:Iter() do arr[#arr + 1] = v end
  return arr
end

local function PushLimited(dq, v, maxN)
  dq:PushBack(v)
  while dq:Size() > maxN do dq:PopFront() end
end

local function SafeGetCVarNumber(name, fallback)
  local v = GetCVar(name)
  local n = tonumber(v)
  if not n then return fallback end
  return n
end

local function GetDynamicMicroCap(cfg)
  local sqwMs = SafeGetCVarNumber("SpellQueueWindow", 400)
  local sqw = sqwMs / 1000
  local margin = cfg.microCapMargin; if margin == nil then margin = 0.05 end
  local minV = cfg.microCapMin; if minV == nil then minV = 0.10 end
  local maxV = cfg.microCapMax; if maxV == nil then maxV = 0.40 end
  return U.Clamp(sqw + margin, minV, maxV), sqw, sqwMs
end

local function FindFirstPressBetween(self, tA, tB)
  for e in self.pressQueue:Iter() do
    if e.t >= tA and e.t <= tB then return e end
  end
  return nil
end

local function FindLastPressBetween(self, tA, tB)
  local last = nil
  for e in self.pressQueue:Iter() do
    if e.t >= tA and e.t <= tB then last = e end
  end
  return last
end


local function CountPressBetween(self, tA, tB)
  local n = 0
  for e in self.pressQueue:Iter() do
    if e.t >= tA and e.t <= tB then n = n + 1 end
  end
  return n
end

-- Reuse small arrays in hot paths to reduce GC pressure.
local function ClearArray(t)
  for i = #t, 1, -1 do t[i] = nil end
end

-- Percentile/median for arrays that we are allowed to sort in-place.
local function PercentileSorted(arr, p)
  local n = #arr
  if n == 0 then return 0 end
  local idx = math.floor(U.Clamp(p, 0, 1) * (n - 1) + 1)
  return arr[idx] or 0
end

local function MedianSorted(arr)
  local n = #arr
  if n == 0 then return 0 end
  local mid = math.floor((n + 1) / 2)
  if (n % 2) == 1 then
    return arr[mid] or 0
  end
  return ((arr[mid] or 0) + (arr[mid + 1] or 0)) / 2
end


-- Estimate "system delay" between the moment the GCD becomes ready and when we observe
-- UNIT_SPELLCAST_SUCCEEDED for the next GCD-triggering spell.
--
-- Why:
--   rawGap = start - ready includes network/processing jitter. If we treat it as AFK,
--   we will falsely mark good queued gameplay as "sleeping" on higher ping.
--
-- Strategy:
--   Prefer empirical median from queued-classified cycles (startDelayQueued deque).
--   Fallback: derive from current latency (GetNetStats), using a conservative one-way estimate.
local function EstimateSystemDelaySec(self, cfg)
  -- Empirical: median startDelayQueued (seconds). Needs a few samples to be stable.
  local arr = DequeToArray(self.startDelayQueued or U.Deque:New())
  if #arr >= (cfg.sysDelayMinSamples or 6) then
    local m = U.Median(arr)
    if m and m > 0 and m < 1.0 then
      return m
    end
  end

  -- Fallback from ping.
  local _, _, home, world = GetNetStats()
  local latMs = 0
  if home and world then
    latMs = math.max(tonumber(home) or 0, tonumber(world) or 0)
  else
    latMs = tonumber(world) or tonumber(home) or 0
  end

  -- One-way-ish estimate. Factor < 1 because SpellQueueWindow pre-queues before ready.
  local f = cfg.sysDelayLatencyFactor
  if f == nil then f = 0.50 end
  local s = (latMs * f) / 1000
  -- Clamp to sane range; avoid zero to prevent divide-by-zero style pathologies.
  return U.Clamp(s, 0.01, 0.30)
end

function M:Reset()
  self.inSegment = false
  self.segmentStart = nil
  self.segmentEnd = nil
  self.segmentEndEffective = nil

  self.actualFight = 0

  self.lastGCDStart = nil
  self.lastGCDDur = nil
  self.lastReadyTime = nil

  self.wasteMicroTime = 0
  self.afkTime = 0
  self.tailTime = 0
  self.wastedGCD = 0

  -- lost GCDs by confirmed cycle length (true "missed globals")
  self.lostTime = 0
  self.lostGcd = 0

  self.gcdStarts = U.Deque:New()
  self.intervals = U.Deque:New()
  self.gapFull = U.Deque:New()

  -- breakdown samples (seconds)
  self.queueLead = U.Deque:New()        -- ready - press (queued-classified)
  self.startDelayQueued = U.Deque:New() -- start - ready (queued-classified)
  self.latePress = U.Deque:New()        -- press - ready (late-classified)
  self.afterPressLate = U.Deque:New()   -- start - press (late-classified)

  -- per-cycle snapshots for SQW recommendation (seconds)
  -- each: {ready=number, start=number, presses={t1,t2,...}}
  self.cycleData = U.Deque:New()

  -- per-cycle compact log for rolling window analytics
  -- each: {t=start, prevDur=, delta=, lost=, delay=, class=, noPress=bool, qCov=bool, qMulti=bool,
  --        late=bool, lateDelay=, afterLate=, qDelay=}
  self.cycleLog = U.Deque:New()

  -- counts (classified)
  self.cycleN = 0
  self.queuedN = 0
  self.lateN = 0
  self.noneN = 0

  -- NEW: coverage / AFK-press
  self.queueCovN = 0        -- any press in [ready-SQW, ready] (even if late later)
  self.queueMultiN = 0      -- 2+ presses in [ready-SQW, ready] (over-queue risk)
  self.afkGapN = 0          -- cycles with gap > MicroCap
  self.afkGapPressN = 0     -- those cycles where press in [ready+MicroCap, start]

  -- server delay non-zero share among queued-classified
  self.queuedDelayNonZeroN = 0

  -- press queue
  self.pressQueue = U.Deque:New() -- {t=, kind=, id=}
end

function M:OnSegmentStart(t0)
  self:Reset()
  self.inSegment = true
  self.segmentStart = t0
end

function M:OnSegmentEnd(t1)
  self.inSegment = false
  self.segmentEnd = t1

  -- Effective end: cut idle tail after the last meaningful input/action for the final report.
  -- We use max(last GCD start, last press attempt) to avoid cutting off a queued final start.
  local effEnd = t1
  local lastAction = 0
  if self.lastGCDStart and self.lastGCDStart > lastAction then lastAction = self.lastGCDStart end
  if self.lastPressAt and self.lastPressAt > lastAction then lastAction = self.lastPressAt end
  if lastAction > 0 and effEnd and effEnd > lastAction then
    effEnd = lastAction
  end
  if self.segmentStart and effEnd and effEnd < self.segmentStart then
    effEnd = self.segmentStart
  end
  self.segmentEndEffective = effEnd

  -- Tail time is kept for display, but NOT added into AFK in final report
  -- because we cut it via segmentEndEffective.
  self.tailTime = 0
end

function M:GetEffectiveEnd(now)
  if self.inSegment then return now or GetTime() end
  return self.segmentEndEffective or self.segmentEnd or (now or GetTime())
end

function M:ReanchorStart(newStart)
  self.segmentStart = newStart
end

function M:OnPress(now, kind, id)
  if not self.inSegment then return end

  local cfg = NS:GetConfig()
  local bufSec = cfg.pressBufferSeconds or 8.0
  local bufMax = cfg.pressBufferMax or 1200

  self.pressQueue:PushBack({ t = now, kind = kind, id = id })

  self.lastPressAt = now

  self.pressQueue:PopFrontWhile(function(e)
    return e.t < (now - bufSec)
  end)

  while self.pressQueue:Size() > bufMax do
    self.pressQueue:PopFront()
  end
end

function M:OnGCDStart(gcdStart, gcdDurObserved)
  if not self.inSegment then return end

  local cfg = NS:GetConfig()
  local statN = cfg.statWindowN or 60

  self.actualFight = self.actualFight + 1
  self.gcdStarts:PushBack(gcdStart)

  if self.lastGCDStart then
    local delta = gcdStart - self.lastGCDStart
    if delta > 0 and delta < 10 then
      self.cycleN = (self.cycleN or 0) + 1
      PushLimited(self.intervals, delta, statN)

      local prevDur = self.lastGCDDur or 0
      -- True lost GCDs from cycle length. Uses confirm-to-confirm distance only.
      -- lostG = floor(delta / prevDur) - 1 (clamped), where prevDur is our last observed/predicted GCD.
      if prevDur and prevDur > 0 then
        local lost = math.floor((delta + 1e-6) / prevDur) - 1
        if lost < 0 then lost = 0 end
        -- Allow large downtime to be reflected in LostG (used for training).
        -- Keep a high cap to prevent numeric blowups from extreme edge cases.
        if lost > 30 then lost = 30 end
        self.lostGcd = (self.lostGcd or 0) + lost
        self.lostTime = (self.lostTime or 0) + (lost * prevDur)
      end

      local ready = self.lastGCDStart + prevDur
      self.lastReadyTime = ready

      local rawGap = gcdStart - ready
      if rawGap < 0 then rawGap = 0 end

      -- microcap
      local capSec
      if cfg.dynamicMicroCap == false then
        capSec = cfg.microCap or 0.20
      else
        capSec = select(1, GetDynamicMicroCap(cfg))
      end

      -- SQW
      local sqwMs = SafeGetCVarNumber("SpellQueueWindow", 400)
      local sqwSec = sqwMs / 1000

      -- Snapshot press times around this cycle for later SQW recommendation.
      do
        local snap = { ready = ready, start = gcdStart, presses = {} }
        local tMin = ready - 0.60 -- cover up to 400ms queue + margin
        for e in self.pressQueue:Iter() do
          if e.t >= tMin and e.t <= gcdStart then
            snap.presses[#snap.presses + 1] = e.t
          end
        end
        PushLimited(self.cycleData, snap, statN)
      end

      -- Coverage: any press in queue window (even if later becomes "late")
      local qP = FindLastPressBetween(self, ready - sqwSec, ready)
if qP then
  self.queueCovN = (self.queueCovN or 0) + 1
  local k = CountPressBetween(self, ready - sqwSec, ready)
  if k >= 2 then
    self.queueMultiN = (self.queueMultiN or 0) + 1
  end
end


      -- Classification (late > queued > none), but reuse qP computed above
      local lateP = FindFirstPressBetween(self, ready, gcdStart)
      local class = "none"
      if lateP then class = "late" elseif qP then class = "queued" end

      -- System delay compensation.
      -- rawGap = start - ready includes network/processing jitter. We remove an estimate of that
      -- before using the gap for player-skill metrics.
      local sysDelay = EstimateSystemDelaySec(self, cfg)
      local delay = rawGap - sysDelay
      if delay < 0 then delay = 0 end

      -- Store (delay) for HUD (Gap90) and downstream analysis.
      PushLimited(self.gapFull, delay, statN)
      -- Micro/AFK breakdown (matches the user guide):
      -- delay = max(0, (start - ready) - sysDelay). This is the player-visible "gap" after GCD becomes ready.
      -- micro = small part of delay (capped by MicroCap); AFK = the remainder of delay beyond MicroCap.
      local micro = delay
      if micro > capSec then micro = capSec end
      local afk = delay - micro
      if afk < 0 then afk = 0 end

      -- AFK-gap diagnostic: for cycles with a real AFK component (delay > MicroCap),
      -- did the player press during the AFK portion [ready+MicroCap, start]?
      local isAfkGap = delay > (capSec + 1e-6)
      local afkPress = false
      if isAfkGap then
        local afkStart = ready + capSec
        if afkStart < gcdStart and FindFirstPressBetween(self, afkStart, gcdStart) then
          afkPress = true
        end
      end

      -- Rolling analytics log (compact per-cycle record)
      do
        local lost = 0
        if prevDur and prevDur > 0 then
          lost = math.floor((delta + 1e-6) / prevDur) - 1
          if lost < 0 then lost = 0 end
          if lost > 30 then lost = 30 end
        end
        local qDelay = (class == "queued") and rawGap or nil
        local lateDelay = (lateP and (lateP.t - ready)) or 0
        local afterLate = (lateP and (gcdStart - lateP.t)) or 0
        PushLimited(self.cycleLog, {
          t = gcdStart,
          prevDur = prevDur,
          delta = delta,
          lost = lost,
          delay = delay,
          capSec = capSec,
          micro = micro,
          afk = afk,
          class = class,
          noPress = (class == "none"),
          qCov = (qP ~= nil),
          qMulti = (qP ~= nil) and (CountPressBetween(self, ready - sqwSec, ready) >= 2) or false,
          late = (class == "late"),
          lateDelay = lateDelay,
          afterLate = afterLate,
          qDelay = qDelay,
          afkGap = isAfkGap,
          afkPress = afkPress,
        }, 600)
      end

      self.wasteMicroTime = self.wasteMicroTime + micro
      self.afkTime = self.afkTime + afk
      if prevDur and prevDur > 0 then
        -- WstG = player-induced gap in "GCD equivalents" (not counting system delay).
        self.wastedGCD = self.wastedGCD + (micro / prevDur)
      end
      -- AFKp% semantics:
      -- Consider cycles with a real AFK component (delay > MicroCap). AFKp answers:
      -- "During those AFK gaps, did you press at least once (after MicroCap)?".
      if isAfkGap then
        self.afkGapN = (self.afkGapN or 0) + 1
        if afkPress then
          self.afkGapPressN = (self.afkGapPressN or 0) + 1
        end
      end

      if class == "late" then
        self.lateN = (self.lateN or 0) + 1

        local late = lateP.t - ready
        local after = gcdStart - lateP.t
        if late < 0 then late = 0 end
        if after < 0 then after = 0 end

        PushLimited(self.latePress, late, statN)
        PushLimited(self.afterPressLate, after, statN)
      elseif class == "queued" then
        self.queuedN = (self.queuedN or 0) + 1

        local lead = ready - qP.t
        local sd = rawGap
        if lead < 0 then lead = 0 end
        if sd < 0 then sd = 0 end

        PushLimited(self.queueLead, lead, statN)
        PushLimited(self.startDelayQueued, sd, statN)

        local eps = 0.002 -- 2ms
        if sd > eps then
          self.queuedDelayNonZeroN = (self.queuedDelayNonZeroN or 0) + 1
        end
      else
        self.noneN = (self.noneN or 0) + 1
      end
    end
  end

  self.lastGCDStart = gcdStart
  self.lastGCDDur = gcdDurObserved or 0
  self.lastReadyTime = self.lastGCDStart + (self.lastGCDDur or 0)
end

-- Build a context snapshot for HUD/analysis.
-- If windowSec is provided, aggregates only cycles with start time in [end-windowSec, end].
-- If cutoffEnd is provided, ignores cycles after cutoffEnd (used for final report tail-cut).
function M:ComputeContext(windowSec, now, cutoffEnd)
  now = now or GetTime()
  local tEnd = cutoffEnd or self:GetEffectiveEnd(now)
  local t0 = self.segmentStart or tEnd
  local tStart = t0
  if windowSec and windowSec > 0 then
    tStart = math.max(t0, tEnd - windowSec)
  end

  local cycles = 0
  local actual = 0
  local lostG = 0
  local wastedG = 0
  local microTime = 0
  local afkTime = 0
  local noPressN = 0
  local lateN = 0
  local queuedN = 0
  local qCovN = 0
  local qMultiN = 0

  local afkGapN = 0
  local afkGapPressN = 0

  -- Reuse arrays across calls (HUD calls this frequently during combat).
  self._tmpGaps = self._tmpGaps or {}
  self._tmpLateDelays = self._tmpLateDelays or {}
  self._tmpAfterLates = self._tmpAfterLates or {}
  self._tmpQDelays = self._tmpQDelays or {}
  self._tmpPrevDurs = self._tmpPrevDurs or {}

  local gaps = self._tmpGaps
  local lateDelays = self._tmpLateDelays
  local afterLates = self._tmpAfterLates
  local qDelays = self._tmpQDelays
  local prevDurs = self._tmpPrevDurs

  ClearArray(gaps)
  ClearArray(lateDelays)
  ClearArray(afterLates)
  ClearArray(qDelays)
  ClearArray(prevDurs)

  for e in self.cycleLog:Iter() do
    if e.t >= tStart and e.t <= tEnd then
      cycles = cycles + 1
      actual = actual + 1 -- each record corresponds to one confirmed GCD start after the first
      lostG = lostG + (e.lost or 0)
      if e.prevDur and e.prevDur > 0 then
        wastedG = wastedG + ((e.micro or 0) / e.prevDur)
      end
      microTime = microTime + (e.micro or 0)
      afkTime = afkTime + (e.afk or 0)
      if e.afkGap then afkGapN = afkGapN + 1 end
      if e.afkPress then afkGapPressN = afkGapPressN + 1 end
      if e.noPress then noPressN = noPressN + 1 end
      if e.late then lateN = lateN + 1 end
      if e.class == "queued" then queuedN = queuedN + 1 end
      if e.qCov then qCovN = qCovN + 1 end
      if e.qMulti then qMultiN = qMultiN + 1 end

      gaps[#gaps + 1] = e.delay or 0
      if e.late and e.lateDelay then lateDelays[#lateDelays + 1] = math.max(0, e.lateDelay) end
      if e.late and e.afterLate then afterLates[#afterLates + 1] = math.max(0, e.afterLate) end
      if e.qDelay then qDelays[#qDelays + 1] = math.max(0, e.qDelay) end
      if e.prevDur and e.prevDur > 0 then prevDurs[#prevDurs + 1] = e.prevDur end
    end
  end

  local dur = math.max(0, tEnd - tStart)
  if #prevDurs > 1 then table.sort(prevDurs) end
  local gcdNow = MedianSorted(prevDurs) or (self.lastGCDDur or 0) or 0
  if gcdNow <= 0 then gcdNow = 1.5 end

  local possibleStarts = actual + lostG
  local eff = (possibleStarts > 0) and (actual / possibleStarts) or 0

  if #gaps > 1 then table.sort(gaps) end
  if #lateDelays > 1 then table.sort(lateDelays) end
  if #afterLates > 1 then table.sort(afterLates) end
  if #qDelays > 1 then table.sort(qDelays) end

  local gapP90 = PercentileSorted(gaps, 0.90)
  local lateP90Ms = PercentileSorted(lateDelays, 0.90) * 1000
  local afterP90Ms = PercentileSorted(afterLates, 0.90) * 1000
  local qDelayP90Ms = PercentileSorted(qDelays, 0.90) * 1000

  local noPressPct = (cycles > 0) and (noPressN / cycles) or 0
  local lateShare = (cycles > 0) and (lateN / cycles) or 0
  local qHit = (cycles > 0) and (queuedN / cycles) or 0
  local qCov = (cycles > 0) and (qCovN / cycles) or 0
  local qMultiShare = (cycles > 0) and (qMultiN / cycles) or 0

  local sysDelaySec = EstimateSystemDelaySec(self, NS:GetConfig())

  local idleSec = self:GetSecondsSinceLastPress(now)

  -- Reuse output table to reduce garbage; HUD consumes it immediately.
  self._ctxOut = self._ctxOut or {}
  local out = self._ctxOut

  out.dur = dur
  out.durSec = dur
  out.elapsedSec = (self.segmentStart and (tEnd - self.segmentStart)) or 0
  out.cycles = cycles
  out.actualFight = actual
  out.eff = eff
  out.possibleStarts = possibleStarts
  out.lostG = lostG
  out.wastedG = wastedG
  out.microTime = microTime
  out.afkTime = afkTime
  out.tailG = 0
  out.gapP90Sec = gapP90
  out.qHit = qHit
  out.qCov = qCov
  out.qMultiShare = qMultiShare
  out.noPressPct = noPressPct
  out.lateShare = lateShare
  out.lateP90Ms = lateP90Ms
  out.afterP90Ms = afterP90Ms
  out.qDelayP90Ms = qDelayP90Ms
  out.sysDelaySec = sysDelaySec
  out.gcdNowSec = gcdNow
  out.idleSec = idleSec
  out.afkDen = afkGapN
  out.afkPressPct = (afkGapN > 0) and (afkGapPressN / afkGapN) or 0

  return out
end

-- getters
function M:GetSecondsSinceLastPress
(now)
  local t = self.lastPressAt or 0
  if t <= 0 then return 1e9 end
  return (now or GetTime()) - t
end

function M:GetFightDuration(now)
  if not self.segmentStart then return 0 end
  if self.inSegment then return (now or GetTime()) - self.segmentStart end
  if self.segmentEnd or self.segmentEndEffective then return (self.segmentEndEffective or self.segmentEnd) - self.segmentStart end
  return 0
end

function M:GetActualFight() return self.actualFight or 0 end

function M:GetActualWindow(now, windowSeconds)
  if not self.inSegment then return 0 end
  local W = windowSeconds or 60
  local cutoff = now - W
  self.gcdStarts:PopFrontWhile(function(t) return t < cutoff end)
  return self.gcdStarts:Size()
end

-- GCD starts per minute over the last 10 seconds.
-- (Called "APM10" in the HUD for familiarity.)
function M:GetAPM10(now)
  now = now or GetTime()
  local n = self:GetActualWindow(now, 10)
  return n * 6
end

-- Median measured GCD cycle time (seconds) from recent intervals.
function M:GetMedianGCD()
  local s = self:GetIntervalStats()
  return (s and s.median) or 0
end

function M:GetWasteMicroTime() return self.wasteMicroTime or 0 end
function M:GetAFKTime() return self.afkTime or 0 end
function M:GetTailTime() return self.tailTime or 0 end
function M:GetWastedGCD() return self.wastedGCD or 0 end
function M:GetLostTime() return self.lostTime or 0 end
function M:GetLostGcd() return self.lostGcd or 0 end
function M:GetLastReadyTime() return self.lastReadyTime end

function M:GetCurrentGap(atTime)
  local t = self.lastReadyTime
  if not t then return 0 end
  local g = (atTime or GetTime()) - t
  if g < 0 then g = 0 end
  return g
end

function M:GetIntervalStats()
  local arr = DequeToArray(self.intervals)
  return { mean = U.Mean(arr), median = U.Median(arr), p90 = U.Percentile(arr, 0.90), n = #arr }
end

function M:GetGapStatsFull()
  local arr = DequeToArray(self.gapFull)
  return { mean = U.Mean(arr), median = U.Median(arr), p90 = U.Percentile(arr, 0.90), n = #arr }
end

function M:GetQueueLeadStats()
  local arr = DequeToArray(self.queueLead)
  return { mean = U.Mean(arr), median = U.Median(arr), p90 = U.Percentile(arr, 0.90), n = #arr }
end

function M:GetStartDelayQueuedStats()
  local arr = DequeToArray(self.startDelayQueued)
  return { mean = U.Mean(arr), median = U.Median(arr), p90 = U.Percentile(arr, 0.90), n = #arr }
end

function M:GetLatePressStats()
  local arr = DequeToArray(self.latePress)
  return { mean = U.Mean(arr), median = U.Median(arr), p90 = U.Percentile(arr, 0.90), n = #arr }
end

function M:GetAfterPressLateStats()
  local arr = DequeToArray(self.afterPressLate)
  return { mean = U.Mean(arr), median = U.Median(arr), p90 = U.Percentile(arr, 0.90), n = #arr }
end

function M:GetPressClassCounts()
  return {
    cycles = self.cycleN or 0,
    queued = self.queuedN or 0,
    late = self.lateN or 0,
    none = self.noneN or 0,
  }
end

-- QC% across cycles
function M:GetQueueCoverageShare()
  local cycles = self.cycleN or 0
  local n = self.queueCovN or 0
  local share = (cycles > 0) and (n / cycles) or 0
  return n, cycles, share
end


function M:GetQueueMultiShare()
  local cycles = self.cycleN or 0
  local n = self.queueMultiN or 0
  local share = (cycles > 0) and (n / cycles) or 0
  return n, cycles, share
end

function M:GetSystemDelaySec()
  return self.sysDelaySec or 0
end


-- AFKp% among AFK-gap cycles (gap > MicroCap)
function M:GetAFKPressShare()
  local denom = self.afkGapN or 0
  local n = self.afkGapPressN or 0
  local share = (denom > 0) and (n / denom) or 0
  return n, denom, share
end

-- SDq>0% among queued-classified
function M:GetQueuedDelayNonZeroShare()
  local q = self.queuedN or 0
  local n = self.queuedDelayNonZeroN or 0
  local share = (q > 0) and (n / q) or 0
  return n, q, share
end


-- Recommend SpellQueueWindow (ms) based on recent cycles, player latency, and press behavior.
-- Goal: high queue coverage (press in [ready-SQW, ready]) while minimizing multi-press inside the window.
-- Returns: recMs, diagTable
function M:RecommendSpellQueueWindow()
  local cfg = NS:GetConfig()
  local cycles = DequeToArray(self.cycleData or U.Deque:New())
  local n = #cycles
  local diag = { sampleN = n }
  if n < (cfg.recommendMinSamples or 20) then
    diag.lowSample = true
  end

  -- latency (ms). GetNetStats returns home/world latency in ms.
  local _, _, home, world = GetNetStats()
  local lat = tonumber(world) or tonumber(home) or 0
  if home and world then lat = math.max(home, world) end
  diag.latencyMs = lat

  local function eval(wMs)
    local w = wMs / 1000
    local cov, multi, none = 0, 0, 0
    for i = 1, n do
      local c = cycles[i]
      local r = c.ready
      local presses = c.presses or {}
      local k = 0
      for j = 1, #presses do
        local t = presses[j]
        if t >= (r - w) and t <= r then
          k = k + 1
        end
      end
      if k >= 1 then cov = cov + 1 else none = none + 1 end
      if k >= 2 then multi = multi + 1 end
    end
    local covS = (n > 0) and (cov / n) or 0
    local multiS = (n > 0) and (multi / n) or 0
    local noneS = (n > 0) and (none / n) or 0
    -- penalty weights tuned for: avoid double-queue more than chasing absolute coverage.
    local score = covS - 1.8 * multiS - 0.6 * noneS
    return score, covS, multiS, noneS
  end

  -- Candidate search. Lower bound influenced by latency (need enough window to pre-queue despite ping).
  local minMs = math.floor(math.max(50, (lat * (cfg.recommendLatencyFactor or 1.0))))
  local maxMs = cfg.recommendMaxMs or 400
  local step = cfg.recommendStepMs or 5

  local bestMs, bestScore = nil, -1e9
  local bestCov, bestMulti, bestNone = 0, 0, 0
  for wMs = minMs, maxMs, step do
    local score, covS, multiS, noneS = eval(wMs)
    if score > bestScore then
      bestScore = score
      bestMs = wMs
      bestCov, bestMulti, bestNone = covS, multiS, noneS
    end
  end

  -- Fallback if no cycles.
  if not bestMs then bestMs = 400 end

  diag.bestScore = bestScore
  diag.coverage = bestCov
  diag.multi = bestMulti
  diag.noQueue = bestNone

  -- Conservative snap: add small buffer derived from user's typical early lead (median queueLead).
  local leads = DequeToArray(self.queueLead or U.Deque:New())
  table.sort(leads)
  local medLead = 0
  if #leads >= 1 then
    medLead = leads[math.floor((#leads + 1) / 2)] * 1000
  end
  diag.medianLeadMs = medLead
  local extra = cfg.recommendLeadBufferMs
  if extra == nil then extra = math.floor(math.max(20, math.min(80, medLead))) end
  diag.extraMs = extra

  local rec = bestMs
  -- Ensure recommended is not below latency+buffer. This pushes towards values like 160ms at 100ms ping.
  rec = math.max(rec, math.floor(lat + extra))
  rec = math.max(0, math.min(maxMs, rec))
  diag.recommendedMs = rec

  return rec, diag
end
