-- GCDOptimizer_GCDEstimator.lua
-- Midnight-safe predicted GCD model with multi-source fallbacks.
--
-- Goal:
--  1) In Retail, we can read UnitSpellHaste / GCD cooldown directly.
--  2) In Midnight combat, many combat-related numbers can become Secret.
--     Any arithmetic / comparisons with Secret hard-errors.
--
-- Strategy:
--  A) Prefer *explicit* GCD duration when it is readable (non-Secret):
--     - C_Spell.GetSpellCooldown(61304) or GetSpellCooldown(61304)
--  B) Otherwise estimate haste via auto-attack speed (UnitAttackSpeed):
--     - record a baseline swing speed out-of-combat (non-Secret)
--     - infer haste multiplier as (baselineSwing / currentSwing)
--     - GCD ~= baselineGCD / hasteMultiplier (clamped)
--  C) Continuous correction from observed cast-to-cast deltas (player-only),
--     which are based on local timestamps (GetTime) and thus non-Secret.
--
-- Notes / limits:
--  - Auto-attack *speed* is assumed to be readable (based on existing retail behavior),
--    but we still guard with issecretvalue() to avoid crashes if Blizzard changes this.
--  - Observed deltas include human delay; we treat them as an upper bound signal and
--    use robust smoothing, not direct replacement.
--
-- Exposes:
--   NS.GCDEstimator:GetPredictedGCD() -> number (always non-Secret)
--   NS.GCDEstimator:OnGCDStart(tStart, observedDurMaybe)
--   NS.GCDEstimator:OnPlayerCastSuccess(spellID)
--
local _, NS = ...
local U = NS.Util

NS.GCDEstimator = NS.GCDEstimator or {}
local E = NS.GCDEstimator

local GCD_SPELL_ID = 61304

local function Now() return GetTime() end

local function IsSecret(v)
  return type(v) ~= "nil" and type(issecretvalue) == "function" and issecretvalue(v)
end

local function Clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function ReadGCDCooldown()
  -- Returns numeric startTime/duration if available; otherwise nils.
  local st, dur
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
    if type(info) == "table" then
      st, dur = info.startTime, info.duration
    end
  else
    st, dur = GetSpellCooldown(GCD_SPELL_ID)
  end

  if IsSecret(st) or IsSecret(dur) then
    return nil, nil
  end
  st = tonumber(st or 0) or 0
  dur = tonumber(dur or 0) or 0
  if st <= 0 or dur <= 0 then
    return nil, nil
  end
  return st, dur
end

local function GetSwingSpeed()
  -- Returns a numeric swing speed (seconds per swing) or nil if unavailable/Secret.
  if not UnitAttackSpeed then return nil end
  local mh, oh = UnitAttackSpeed("player")
  if IsSecret(mh) then return nil end
  mh = tonumber(mh or 0) or 0
  if mh <= 0 then return nil end
  return mh, oh
end

local function SpellTriggersGCD(spellID)
  if not spellID then return true end

  if C_Spell and C_Spell.DoesSpellTriggerGlobalCooldown then
    local ok = C_Spell.DoesSpellTriggerGlobalCooldown(spellID)
    if IsSecret(ok) then
      return true
    end
    if type(ok) == "boolean" then return ok end
  end

  -- Conservative fallback: treat as triggering.
  return true
end

function E:Reset()
  self.baseGCD = 1.5           -- calibrated out-of-combat when possible
  self.baseSwing = nil         -- baseline swing speed out-of-combat
  self.lastPred = 1.5          -- last returned prediction (stable, non-Secret)

  -- Correction from observed cast deltas
  self.lastCastAt = nil
  self.obsEWMA = nil           -- smoothed observed cycle time (includes human delay)
  self.obsAlpha = 0.20

  -- Bounds (most specs)
  self.minGCD = 0.75
  self.maxGCD = 1.5
end

function E:Init()
  if self._inited then return end
  self._inited = true
  self:Reset()

  -- Out-of-combat baseline sampling: try to learn base swing speed immediately.
  local mh = GetSwingSpeed()
  if mh then self.baseSwing = mh end
end

function E:OnSegmentStart()
  -- Refresh baselines when possible.
  if not InCombatLockdown() then
    local mh = GetSwingSpeed()
    if mh then self.baseSwing = mh end

    local _, dur = ReadGCDCooldown()
    if dur then
      self.baseGCD = Clamp(dur, self.minGCD, self.maxGCD)
      self.lastPred = self.baseGCD
    end
  end

  -- Reset cast observation state each segment to avoid cross-fight bleed.
  self.lastCastAt = nil
  self.obsEWMA = nil
end

function E:OnSegmentEnd()
  -- no-op (kept for symmetry / future)
end

function E:OnGCDStart(_tStart, observedDur)
  -- If caller passes a readable observed duration, prefer it as base.
  if observedDur and not IsSecret(observedDur) then
    local d = tonumber(observedDur) or 0
    if d > 0 then
      self.lastPred = Clamp(d, self.minGCD, self.maxGCD)
      if not InCombatLockdown() then
        -- Out of combat we treat this as the best baseline.
        self.baseGCD = self.lastPred
      end
    end
  end
end

function E:OnPlayerCastSuccess(spellID)
  if not SpellTriggersGCD(spellID) then return end

  local t = Now()
  if self.lastCastAt then
    local dt = t - self.lastCastAt
    -- Basic sanity: ignore long gaps (AFK) and tiny deltas (double-fires)
    if dt > 0.30 and dt < 10.0 then
      if not self.obsEWMA then
        self.obsEWMA = dt
      else
        self.obsEWMA = self.obsEWMA * (1 - self.obsAlpha) + dt * self.obsAlpha
      end
    end
  end
  self.lastCastAt = t
end

function E:GetPredictedGCD()
  -- 1) Direct GCD duration if readable.
  local _, dur = ReadGCDCooldown()
  if dur then
    self.lastPred = Clamp(dur, self.minGCD, self.maxGCD)
    return self.lastPred
  end

  -- 2) Haste via swing speed ratio if possible.
  local mh = GetSwingSpeed()
  if mh and self.baseSwing and self.baseSwing > 0 then
    local hasteMult = self.baseSwing / mh
    -- Guard: extreme / nonsense ratios (weapon swap, stance, bugs)
    if hasteMult > 0.20 and hasteMult < 5.0 then
      local gcd = self.baseGCD / hasteMult
      gcd = Clamp(gcd, self.minGCD, self.maxGCD)
      -- 3) Correction: observed EWMA (upper-bound bias), gently nudge downwards
      -- if we consistently observe very close-to-GCD cycling.
      if self.obsEWMA then
        -- If player is playing well, obsEWMA approaches true cycle time.
        -- We avoid raising gcd from obsEWMA (would bake human delays into the model).
        local corr = Clamp(self.obsEWMA, self.minGCD, self.maxGCD)
        if corr < gcd then
          local beta = 0.15
          gcd = gcd * (1 - beta) + corr * beta
        end
      end

      self.lastPred = gcd
      return self.lastPred
    end
  end

  -- 4) Final fallback: last known stable value.
  return self.lastPred
end

function E:DebugSnapshot()
  -- Returns a plain Lua table with *non-Secret* values only (safe to print).
  return {
    baseGCD = self.baseGCD,
    baseSwing = self.baseSwing,
    lastPred = self.lastPred,
    obsEWMA = self.obsEWMA,
  }
end
