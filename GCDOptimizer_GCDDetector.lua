-- GCDOptimizer_GCDDetector.lua
-- Detects NEW GCD starts by watching spell cooldown 61304 (Global Cooldown).
-- Fixes false double-counting caused by tiny startTime jitter/drift.

local _, NS = ...
local U = NS.Util

NS.GCDDetector = NS.GCDDetector or {}
local D = NS.GCDDetector

local GCD_SPELL_ID = 61304

-- Anti-double-count tuning
-- New GCD starts cannot be closer than ~0.75s in Retail, so 0.50s is safe.
local MIN_NEW_START_DELTA = 0.50
-- Treat small changes in startTime as jitter/drift of the SAME GCD start.
local DRIFT_EPS = 0.10
-- Quantize startTime to reduce floating noise
local function QuantizeTime(t)
  if not t or t <= 0 then return 0 end
  -- 1 ms resolution
  return math.floor(t * 1000 + 0.5) / 1000
end

local function IsSecret(v)
  return type(v) ~= "nil" and type(issecretvalue) == "function" and issecretvalue(v)
end

local function ReadGCDCooldown()
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
    if type(info) == "table" then
      local st, dur = info.startTime or 0, info.duration or 0
      if IsSecret(st) or IsSecret(dur) then return 0, 0 end
      return st, dur
    end
  end
  local startTime, duration = GetSpellCooldown(GCD_SPELL_ID)
  if IsSecret(startTime) or IsSecret(duration) then return 0, 0 end
  return startTime or 0, duration or 0
end


function D:Init()
  if self._inited then return end
  self._inited = true

  local f = CreateFrame("Frame")
  self.frame = f

  f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

  f:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
    if unit ~= "player" then return end
    if not NS.state or not NS.state.inSegment then return end

    -- Use local event time as the best available non-Secret timestamp.
    local t = GetTime()

    -- Feed estimator for correction learning.
    if NS.GCDEstimator then
      NS.GCDEstimator:OnPlayerCastSuccess(spellID)
    end

    -- If this spell triggers the GCD, treat this as a new GCD start.
    local triggers = true
    if C_Spell and C_Spell.DoesSpellTriggerGlobalCooldown and spellID then
      local ok = C_Spell.DoesSpellTriggerGlobalCooldown(spellID)
      if type(issecretvalue) == "function" and issecretvalue(ok) then
        triggers = true
      elseif type(ok) == "boolean" then
        triggers = ok
      end
    end

    if not triggers then return end

    -- Anti-double-count: if polling already counted this GCD (or we counted a moment ago), ignore.
    local last = self.lastCountedStart or 0
    if last > 0 then
      local dt = t - last
      if dt < 0 then dt = -dt end
      if dt <= DRIFT_EPS or dt < MIN_NEW_START_DELTA then
        return
      end
    end

    local gcdDur = 0
    if NS.GCDEstimator and NS.GCDEstimator.GetPredictedGCD then
      gcdDur = NS.GCDEstimator:GetPredictedGCD()
      -- let estimator learn from observed if we later get a direct duration
      NS.GCDEstimator:OnGCDStart(t, nil)
    end

    -- Keep internal state consistent for HUD/debug.
    self.lastCountedStart = t
    self.lastCountedDuration = gcdDur

    NS:OnGCDStart(t, gcdDur)
  end)
end

function D:Reset()
  self.inSegment = false

  if self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end

  -- Last *counted* GCD start (quantized)
  self.lastCountedStart = 0
  self.lastCountedDuration = 0

  -- Last read (for HUD convenience)
  self.liveStart = 0
  self.liveDuration = 0
end

function D:OnSegmentStart()
  self:Reset()
  self.inSegment = true

  local cfg = NS:GetConfig()
  local interval = U.Clamp(cfg.pollInterval or 0.02, 0.01, 0.20)

  -- IMPORTANT:
  -- Do NOT prime lastCountedStart to current cooldown start.
  -- We want to count the first observed GCD in-segment even if it's already running,
  -- because Core may re-anchor segment start to that first GCDStart.
  self.lastCountedStart = 0
  self.lastCountedDuration = 0

  self.ticker = C_Timer.NewTicker(interval, function()
    if not self.inSegment then return end

    local st, dur = ReadGCDCooldown()
    st = QuantizeTime(st)
    dur = dur or 0

    self.liveStart = st
    self.liveDuration = dur

    -- No active GCD
    if st <= 0 or dur <= 0 then
      return
    end

    local last = self.lastCountedStart or 0

    -- If the reported startTime is very close to the last counted start,
    -- treat it as the SAME GCD (jitter/drift). Update stored values and do NOT count.
    if last > 0 and math.abs(st - last) <= DRIFT_EPS then
      self.lastCountedStart = st
      self.lastCountedDuration = dur
      return
    end

    -- A real new GCD start must jump forward enough.
    if (st - last) >= MIN_NEW_START_DELTA then
      self.lastCountedStart = st
      self.lastCountedDuration = dur
      NS:OnGCDStart(st, dur)
      return
    end

    -- Otherwise ignore (covers rare weirdness where st moves backward or tiny forward)
  end)
end

function D:OnSegmentEnd()
  self.inSegment = false
  if self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end
end

function D:GetLastObservedGCD()
  return self.lastCountedDuration or 0
end

function D:GetLiveGCDInfo()
  -- Return the last polled live values if available;
  -- if ticker is not running, do a one-shot read.
  if self.inSegment then
    return self.liveStart or 0, self.liveDuration or 0
  end

  local st, dur = ReadGCDCooldown()
  return QuantizeTime(st), dur or 0
end
