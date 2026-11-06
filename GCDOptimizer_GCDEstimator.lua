-- GCDOptimizer_GCDEstimator.lua
-- Hybrid GCD duration model. Exact ordinary 61304 timing is preferred;
-- calibrated attack-speed estimation is used only when the direct numbers are
-- unavailable; cached/default values are display-only low-confidence data.

local _, NS = ...
local U = NS.Util

NS.GCDEstimator = NS.GCDEstimator or {}
local E = NS.GCDEstimator

local DEFAULT_DISPLAY_GCD = 1.5
local MIN_GCD = 0.50
local MAX_GCD = 2.50
local MIN_SWING = 0.20
local MAX_SWING = 10.0

local function Now()
  return GetTime()
end

local function ValidDuration(value)
  return U.IsFiniteNumber(value) and value >= MIN_GCD and value <= MAX_GCD
end

local function ValidSwing(value)
  return U.IsFiniteNumber(value) and value >= MIN_SWING and value <= MAX_SWING
end

function E:Init()
  if self._inited then return end
  self._inited = true
  self:ResetAll()

  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  frame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
  frame:RegisterEvent("SPELL_SECRECY_CHANGED")
  frame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
      if not U.CanAccessValues(unit) or unit ~= "player" then return end
    end
    if event == "SPELL_SECRECY_CHANGED" then
      self.lastPolicyChangeAt = Now()
      return
    end
    self:InvalidateCalibration(event)
  end)
  self.eventFrame = frame
end

function E:ResetAll()
  self.calibrationSwing = nil
  self.calibrationGCD = nil
  self.calibrationAt = nil
  self.calibrationInvalidatedBy = nil
  self.lastStable = nil
  self.lastDirectStart = nil
  self.sampleCount = 0
  self.lastSampleAt = 0
  self.lastPolicyChangeAt = 0
  self:ResetSegment()
end

-- Segment resets deliberately preserve a valid direct/swing calibration.
function E:ResetSegment()
  self.lastPred = self.lastStable or DEFAULT_DISPLAY_GCD
  self.source = U.GCD_SOURCE_CACHED
  self.lastStart = nil
end

-- Kept for the Core compatibility surface; it must not erase calibration.
function E:Reset()
  self:ResetSegment()
end

function E:OnSegmentStart()
  self:ResetSegment()
  local status, startTime, duration = U.ReadGCDObservation()
  if status == U.GCD_STATUS_EXACT then
    self:ObserveDirect(duration, Now(), startTime)
  end
end

function E:OnSegmentEnd()
end

function E:InvalidateCalibration(reason)
  self.calibrationSwing = nil
  self.calibrationGCD = nil
  self.calibrationAt = nil
  self.calibrationInvalidatedBy = reason or "unknown"
  self.source = U.GCD_SOURCE_CACHED
end

function E:ObserveDirect(duration, observedAt, startTime)
  if not ValidDuration(duration) then return false end

  observedAt = observedAt or Now()
  local isNewStart = not startTime
    or not self.lastDirectStart
    or math.abs(startTime - self.lastDirectStart) > 0.05
  self.lastStable = duration
  self.lastPred = duration
  self.source = U.GCD_SOURCE_DIRECT
  if isNewStart then
    self.sampleCount = (self.sampleCount or 0) + 1
    self.lastDirectStart = startTime
  end
  self.lastSampleAt = observedAt

  -- Pair swing speed with the first observation of a new exact GCD. Repeated
  -- polls of the same cooldown may occur after an attack-speed-only effect
  -- changes; recalibrating then would combine a start-time GCD duration with a
  -- later, unrelated swing speed.
  if isNewStart then
    local swing = U.ReadPlayerAttackSpeed()
    if ValidSwing(swing) then
      self.calibrationSwing = swing
      self.calibrationGCD = duration
      self.calibrationAt = observedAt
      self.calibrationInvalidatedBy = nil
    end
  end
  return true
end

function E:GetSwingEstimate()
  local baseSwing = self.calibrationSwing
  local baseGCD = self.calibrationGCD
  if not (ValidSwing(baseSwing) and ValidDuration(baseGCD)) then
    return nil
  end

  local currentSwing = U.ReadPlayerAttackSpeed()
  if not ValidSwing(currentSwing) then return nil end

  local estimate = baseGCD * (currentSwing / baseSwing)
  if not ValidDuration(estimate) then return nil end
  return estimate
end

function E:GetFallbackPrediction()
  local estimated = self:GetSwingEstimate()
  if estimated then
    self.lastPred = estimated
    self.source = U.GCD_SOURCE_ESTIMATED
    return estimated, U.GCD_SOURCE_ESTIMATED
  end

  local cached = self.lastStable or DEFAULT_DISPLAY_GCD
  self.lastPred = cached
  self.source = U.GCD_SOURCE_CACHED
  return cached, U.GCD_SOURCE_CACHED
end

function E:GetPrediction()
  local status, startTime, duration = U.ReadGCDObservation()
  if status == U.GCD_STATUS_EXACT and self:ObserveDirect(duration, Now(), startTime) then
    return duration, U.GCD_SOURCE_DIRECT
  end
  return self:GetFallbackPrediction()
end

function E:OnGCDStart(startTime, duration, source)
  self.lastStart = startTime
  if source == U.GCD_SOURCE_DIRECT then
    self:ObserveDirect(duration, Now(), startTime)
  elseif source == U.GCD_SOURCE_ESTIMATED and ValidDuration(duration) then
    self.lastPred = duration
    self.source = source
  end
end

function E:DebugSnapshot()
  return {
    lastPred = self.lastPred or self.lastStable or DEFAULT_DISPLAY_GCD,
    source = self.source or U.GCD_SOURCE_CACHED,
    sampleCount = self.sampleCount or 0,
    lastSampleAt = self.lastSampleAt or 0,
    calibrationSwing = self.calibrationSwing,
    calibrationGCD = self.calibrationGCD,
    calibrationAt = self.calibrationAt,
    calibrationInvalidatedBy = self.calibrationInvalidatedBy,
    lastPolicyChangeAt = self.lastPolicyChangeAt or 0,
  }
end
