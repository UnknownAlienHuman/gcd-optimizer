-- GCDOptimizer_GCDDetector.lua
-- One owner for generic GCD start detection. Cooldown events/ticker prefer
-- exact 61304 timing. Player spell-success events are wake signals only and may
-- produce an estimated start only when the NeverSecret activity flag confirms
-- that the generic GCD is active.

local _, NS = ...
local U = NS.Util

NS.GCDDetector = NS.GCDDetector or {}
local D = NS.GCDDetector

local MIN_NEW_START_DELTA = 0.45
local SAME_START_EPSILON = 0.05
local ESTIMATE_UPGRADE_WINDOW = 0.35
local FALLBACK_DELAY = 0.06
local CONTINUOUS_ACTIVE_MIN_FRACTION = 0.90
local DURATION_REFRESH_EPSILON = 0.001

local SOURCE_RANK = {
  [U.GCD_SOURCE_CACHED] = 0,
  [U.GCD_SOURCE_ESTIMATED] = 1,
  [U.GCD_SOURCE_DIRECT] = 2,
}

local function Now()
  return GetTime()
end

local function ValidStart(value)
  return U.IsFiniteNumber(value) and value > 0
end

local function ValidDuration(value)
  return U.IsFiniteNumber(value) and value >= 0.50 and value <= 2.50
end

function D:Init()
  if self._inited then return end
  self._inited = true

  local frame = CreateFrame("Frame")
  frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
  frame:RegisterEvent("SPELL_SECRECY_CHANGED")
  frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  frame:SetScript("OnEvent", function(_, event)
    if not (NS.state and NS.state.inSegment) then return end

    local eventTime = Now()
    self:Observe(event)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      self:ScheduleEstimatedFallback(eventTime)
    end
  end)
  self.eventFrame = frame
  self:Reset()
end

function D:CancelPendingFallback()
  if self.pendingFallback then
    self.pendingFallback:Cancel()
    self.pendingFallback = nil
  end
  self.pendingGeneration = (self.pendingGeneration or 0) + 1
end

function D:StopTicker()
  self.pollGeneration = (self.pollGeneration or 0) + 1
  if self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end
end

function D:Reset()
  self:StopTicker()
  self:CancelPendingFallback()
  self.lastCountedStart = nil
  self.lastCountedDuration = nil
  self.lastCountedSource = nil
  self.liveStart = nil
  self.liveDuration = nil
  self.liveSource = U.GCD_SOURCE_CACHED
  self.lastStatus = U.GCD_STATUS_UNAVAILABLE
  self.inBlindInterval = false
  self.sawInactiveSinceLastStart = true
  self.requireInactiveBeforeEstimate = false
  self.exactCount = 0
  self.estimatedCount = 0
  self.upgradeCount = 0
end

function D:OnSegmentStart()
  self:Reset()
  local cfg = NS:GetConfig()
  local interval = U.Clamp(cfg.pollInterval or 0.05, 0.03, 0.25)
  local generation = self.pollGeneration
  self.ticker = C_Timer.NewTicker(interval, function()
    if generation ~= self.pollGeneration then return end
    if NS.state and NS.state.inSegment then self:Observe("ticker") end
  end)

  local status = self:Observe("segment_start")
  if not (NS.state and NS.state.autoCombat)
    and not self.lastCountedStart
    and (status == U.GCD_STATUS_EXACT or status == U.GCD_STATUS_ACTIVE_RESTRICTED)
  then
    -- A manual segment started in the middle of an already-active GCD. With no
    -- post-start transition we cannot claim that cycle as belonging to it.
    self.requireInactiveBeforeEstimate = true
  end
end

function D:OnSegmentEnd()
  self:StopTicker()
  self:CancelPendingFallback()
end

function D:IsBeforeManualSegment(startTime)
  local state = NS.state
  if not (state and state.segmentStart) then return false end
  if startTime >= state.segmentStart then return false end
  return not state.autoCombat
end

function D:AcceptStart(startTime, duration, source)
  if not (NS.state and NS.state.inSegment) then return false end
  if source ~= U.GCD_SOURCE_DIRECT and source ~= U.GCD_SOURCE_ESTIMATED then return false end
  if not (ValidStart(startTime) and ValidDuration(duration)) then return false end
  if self:IsBeforeManualSegment(startTime) then return false end

  local previousStart = self.lastCountedStart
  local previousSource = self.lastCountedSource
  if previousStart then
    local delta = startTime - previousStart
    local absoluteDelta = math.abs(delta)

    if source == U.GCD_SOURCE_DIRECT
      and previousSource == U.GCD_SOURCE_ESTIMATED
      and absoluteDelta <= ESTIMATE_UPGRADE_WINDOW
    then
      self.lastCountedStart = startTime
      self.lastCountedDuration = duration
      self.lastCountedSource = source
      self.liveStart = startTime
      self.liveDuration = duration
      self.liveSource = source
      self.exactCount = (self.exactCount or 0) + 1
      self.estimatedCount = math.max(0, (self.estimatedCount or 0) - 1)
      self.upgradeCount = (self.upgradeCount or 0) + 1
      if NS.OnGCDUpgrade then
        NS:OnGCDUpgrade(previousStart, startTime, duration, source)
      end
      return true
    end

    if absoluteDelta <= SAME_START_EPSILON then
      -- A same-cycle lower-quality observation must never overwrite exact
      -- timing. Also avoid forwarding an unchanged direct duration on every
      -- detector poll; that would bypass the HUD's own bounded ticker.
      local previousDuration = self.lastCountedDuration
      local previousRank = SOURCE_RANK[previousSource] or 0
      local currentRank = SOURCE_RANK[source] or 0
      if currentRank >= previousRank then
        local durationChanged = not previousDuration
          or math.abs(duration - previousDuration) > DURATION_REFRESH_EPSILON
        self.lastCountedDuration = duration
        if durationChanged
          and source == U.GCD_SOURCE_DIRECT
          and previousSource == U.GCD_SOURCE_DIRECT
          and NS.OnGCDRefresh
        then
          NS:OnGCDRefresh(previousStart, duration, source)
        end
      end
      return false
    end
    if delta < MIN_NEW_START_DELTA then return false end
  end

  self.lastCountedStart = startTime
  self.lastCountedDuration = duration
  self.lastCountedSource = source
  self.sawInactiveSinceLastStart = false
  self.requireInactiveBeforeEstimate = false
  self.liveStart = startTime
  self.liveDuration = duration
  self.liveSource = source

  if source == U.GCD_SOURCE_DIRECT then
    self.exactCount = (self.exactCount or 0) + 1
  elseif source == U.GCD_SOURCE_ESTIMATED then
    self.estimatedCount = (self.estimatedCount or 0) + 1
  end

  NS:OnGCDStart(startTime, duration, source)
  return true
end

function D:HandleDirect(startTime, duration)
  self.liveStart = startTime
  self.liveDuration = duration
  self.liveSource = U.GCD_SOURCE_DIRECT
  if NS.GCDEstimator then
    NS.GCDEstimator:ObserveDirect(duration, Now(), startTime)
  end
  if NS.OnGCDObservation then
    NS:OnGCDObservation(Now(), duration, U.GCD_SOURCE_DIRECT)
  end
  return self:AcceptStart(startTime, duration, U.GCD_SOURCE_DIRECT)
end

function D:Observe(reason)
  local status, startTime, duration = U.ReadGCDObservation()
  if status == U.GCD_STATUS_EXACT
    and not (ValidStart(startTime) and ValidDuration(duration))
  then
    status = U.GCD_STATUS_MALFORMED
  end
  self.lastStatus = status
  self.lastReason = reason

  local blind = status ~= U.GCD_STATUS_EXACT and status ~= U.GCD_STATUS_INACTIVE
  if reason == "SPELL_SECRECY_CHANGED" then self:CancelPendingFallback() end
  if (blind and not self.inBlindInterval) or reason == "SPELL_SECRECY_CHANGED" then
    if NS.OnGCDObservationGap then NS:OnGCDObservationGap() end
  end
  self.inBlindInterval = blind

  if status == U.GCD_STATUS_EXACT then
    if self.pendingFallback then self:CancelPendingFallback() end
    self:HandleDirect(startTime, duration)
  else
    local predicted, source
    if status == U.GCD_STATUS_INACTIVE or status == U.GCD_STATUS_ACTIVE_RESTRICTED then
      predicted, source = NS.GCDEstimator:GetFallbackPrediction()
    else
      -- No usable observation: never integrate a stale exact rate over the gap.
      source = U.GCD_SOURCE_CACHED
    end
    self.liveStart = nil
    self.liveDuration = status == U.GCD_STATUS_ACTIVE_RESTRICTED and predicted or nil
    self.liveSource = source
    if status == U.GCD_STATUS_INACTIVE then
      self.sawInactiveSinceLastStart = true
      self.requireInactiveBeforeEstimate = false
    end
    if NS.OnGCDObservation then NS:OnGCDObservation(Now(), predicted, source) end
  end

  return status
end

function D:ScheduleEstimatedFallback(eventTime)
  if not (NS.state and NS.state.inSegment) then return end
  if not ValidStart(eventTime) then return end

  -- Even an initially inactive result is deferred once: event ordering can
  -- publish UNIT_SPELLCAST_SUCCEEDED before the GCD activity flag flips. The
  -- callback still requires a confirmed active generic GCD.
  if self.lastStatus == U.GCD_STATUS_EXACT then return end

  self:CancelPendingFallback()
  local generation = self.pendingGeneration
  self.pendingFallback = C_Timer.NewTimer(FALLBACK_DELAY, function()
    if generation ~= self.pendingGeneration then return end
    self.pendingFallback = nil
    if not (NS.state and NS.state.inSegment) then return end

    -- Use the same boundary/integration path as the event and ticker owners.
    local currentStatus = self:Observe("fallback")
    if currentStatus ~= U.GCD_STATUS_ACTIVE_RESTRICTED then return end
    if self.requireInactiveBeforeEstimate then return end

    local predicted, source = NS.GCDEstimator:GetFallbackPrediction()
    if source ~= U.GCD_SOURCE_ESTIMATED or not ValidDuration(predicted) then return end

    local previousStart = self.lastCountedStart
    if previousStart then
      local previousDuration = self.lastCountedDuration or predicted
      local minimumCadence = math.max(
        MIN_NEW_START_DELTA,
        predicted * CONTINUOUS_ACTIVE_MIN_FRACTION,
        previousDuration * CONTINUOUS_ACTIVE_MIN_FRACTION
      )
      if not self.sawInactiveSinceLastStart
        and (eventTime - previousStart) < minimumCadence
      then
        return
      end
    end

    self:AcceptStart(eventTime, predicted, U.GCD_SOURCE_ESTIMATED)
  end)
end

function D:GetLiveGCDInfo()
  return self.liveStart, self.liveDuration, self.liveSource
end

function D:DebugSnapshot()
  return {
    status = self.lastStatus,
    reason = self.lastReason,
    liveStart = self.liveStart,
    liveDuration = self.liveDuration,
    liveSource = self.liveSource,
    exactCount = self.exactCount or 0,
    estimatedCount = self.estimatedCount or 0,
    upgradeCount = self.upgradeCount or 0,
  }
end
