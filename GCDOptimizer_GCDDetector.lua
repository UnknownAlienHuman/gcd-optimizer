-- GCDOptimizer_GCDDetector.lua
-- Detects real GCD starts from the accessible cooldown of spell 61304.
-- UNIT_SPELLCAST_SUCCEEDED only schedules an immediate read; it is never treated
-- as proof that a spell triggered the GCD.

local _, NS = ...
local U = NS.Util

NS.GCDDetector = NS.GCDDetector or {}
local D = NS.GCDDetector

local MIN_NEW_START_DELTA = 0.50
local DRIFT_EPSILON = 0.08

local function QuantizeTime(value)
  return math.floor(value * 1000 + 0.5) / 1000
end

function D:_CountStart(startTime, duration)
  self.lastCountedStart = startTime
  self.lastCountedDuration = duration
  NS:OnGCDStart(startTime, duration)
end

function D:_Poll(countInitial)
  if not self.inSegment then return false end

  local startTime, duration = U.ReadGCDCooldown()
  if not startTime then
    self.liveStart = 0
    self.liveDuration = 0
    return false
  end

  startTime = QuantizeTime(startTime)
  self.liveStart = startTime
  self.liveDuration = duration

  local last = self.lastCountedStart or 0
  if last <= 0 then
    self.lastCountedStart = startTime
    self.lastCountedDuration = duration
    if countInitial ~= false then
      NS:OnGCDStart(startTime, duration)
      return true
    end
    return false
  end

  local delta = startTime - last
  if math.abs(delta) <= DRIFT_EPSILON then
    return false
  end

  if delta >= MIN_NEW_START_DELTA then
    self:_CountStart(startTime, duration)
    return true
  end

  return false
end

function D:_SchedulePoll()
  local generation = self._generation or 0
  if self._pollScheduledGeneration == generation then return end
  self._pollScheduledGeneration = generation

  C_Timer.After(0, function()
    if self._pollScheduledGeneration == generation then
      self._pollScheduledGeneration = nil
    end
    if self.inSegment and generation == (self._generation or 0) then
      self:_Poll()
    end
  end)
end

function D:Init()
  if self._inited then return end
  self._inited = true

  local frame = CreateFrame("Frame")
  self.frame = frame
  frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  frame:RegisterEvent("SPELL_SECRECY_CHANGED")
  frame:SetScript("OnEvent", function()
    if not self.inSegment then return end
    self:_Poll()
    self:_SchedulePoll()
  end)
end

function D:Reset()
  self.inSegment = false
  self._generation = (self._generation or 0) + 1
  self._pollScheduledGeneration = nil

  if self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end

  self.lastCountedStart = 0
  self.lastCountedDuration = 0
  self.liveStart = 0
  self.liveDuration = 0
end

function D:OnSegmentStart()
  self:Reset()
  self.inSegment = true

  local cfg = NS:GetConfig()
  local interval = U.Clamp(cfg.pollInterval or 0.05, 0.03, 0.20)

  local countExisting = NS.state and NS.state.autoCombat and true or false
  self:_Poll(countExisting)
  self.ticker = C_Timer.NewTicker(interval, function()
    self:_Poll()
  end)
end

function D:OnSegmentEnd()
  self.inSegment = false
  self._generation = (self._generation or 0) + 1
  if self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end
end

function D:GetLastObservedGCD()
  return self.lastCountedDuration or 0
end

function D:GetLiveGCDInfo()
  if self.inSegment then
    return self.liveStart or 0, self.liveDuration or 0
  end

  local startTime, duration = U.ReadGCDCooldown()
  if not startTime then return 0, 0 end
  return QuantizeTime(startTime), duration
end
