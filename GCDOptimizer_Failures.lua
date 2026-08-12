-- GCDOptimizer_Failures.lua
-- Tracks cast failures / UI errors while segment is active.
-- Provides window + segment summaries to improve "Bad management" attribution.

local _, NS = ...
local U = NS.Util

NS.Failures = NS.Failures or {}
local F = NS.Failures

local function Now() return GetTime() end

-- Some environments may not have global wipe() available at file load.
-- Keep Failures init resilient; Core SafeCall() swallows errors.
local wipe_ = wipe
if type(wipe_) ~= "function" then
  wipe_ = function(t)
    if type(t) ~= "table" then return end
    for k in pairs(t) do t[k] = nil end
  end
end

-- Safety net: ensure Failures is initialized even if Core init order changes
-- or a previous SafeCall() swallowed an early error.
if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
  C_Timer.After(0, function()
    if F and type(F.Init) == "function" and not F.frame then
      pcall(F.Init, F)
    end
  end)
end

local function IsSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, res = pcall(issecretvalue, v)
  return ok and res or false
end

-- Categories (short tags)
local CAT = {
  RES = "RES",     -- not enough resource/power
  RANGE = "RNG",   -- out of range/too close
  LOS = "LOS",     -- line of sight / in front / behind
  CD = "CD",       -- cooldown/not ready/can't do that yet
  TARGET = "TGT",  -- no/invalid target
  MOVE = "MOV",    -- moving
  OTHER = "OTH",
}

local function Clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function IsSegmentActive()
  return NS.state and NS.state.inSegment
end

local function CatFromStringId(stringId)
  if not stringId or type(stringId) ~= "string" then
    return CAT.OTHER
  end

  local s = stringId

  -- Resource / power
  if s:find("NOT_ENOUGH") or s:find("NO_POWER") or s:find("OUT_OF_") then
    -- tighten OUT_OF_ to resource-ish if possible
    if s:find("MANA") or s:find("ENERGY") or s:find("RAGE") or s:find("FOCUS") or
       s:find("RUNIC") or s:find("FURY") or s:find("PAIN") or s:find("INSANITY") or
       s:find("HOLY_POWER") or s:find("MAELSTROM") or s:find("SOUL_SHARDS") or
       s:find("COMBO") or s:find("CHI") or s:find("ESSENCE") or s:find("ARCANE") then
      return CAT.RES
    end
    -- Some clients use generic "NOT_ENOUGH_*" keys that are still resources.
    if s:find("NOT_ENOUGH") or s:find("NO_POWER") then
      return CAT.RES
    end
  end

  -- Range / proximity
  if s:find("OUT_OF_RANGE") or s:find("RANGE") or s:find("TOO_CLOSE") then
    return CAT.RANGE
  end

  -- LOS / facing
  if s:find("LINE_OF_SIGHT") or s:find("SIGHT") or s:find("IN_FRONT") or s:find("BEHIND") then
    return CAT.LOS
  end

  -- Cooldown / not ready
  if s:find("COOLDOWN") or s:find("NOT_READY") or s:find("CANT_DO_THAT_YET") or s:find("SPELL_FAILED_S") then
    return CAT.CD
  end

  -- Targeting
  if s:find("NO_TARGET") or s:find("BAD_TARGET") or s:find("INVALID_TARGET") or s:find("TARGET") then
    return CAT.TARGET
  end

  -- Moving
  if s:find("MOVING") then
    return CAT.MOVE
  end

  return CAT.OTHER
end

local function CatFromFailedType(failedType)
  if not failedType or type(failedType) ~= "string" then
    return CAT.OTHER
  end

  -- If this is a token like SPELL_FAILED_*
  if failedType:find("^SPELL_FAILED_") then
    local t = failedType
    if t:find("NO_POWER") or t:find("NOT_ENOUGH") or t:find("NO_MANA") or t:find("NO_ENERGY") or t:find("NO_RAGE") then
      return CAT.RES
    end
    if t:find("OUT_OF_RANGE") or t:find("RANGE") or t:find("TOO_CLOSE") then
      return CAT.RANGE
    end
    if t:find("LINE_OF_SIGHT") or t:find("NOT_INFRONT") or t:find("NOT_BEHIND") then
      return CAT.LOS
    end
    if t:find("NOT_READY") or t:find("CANT_DO_THAT_YET") or t:find("COOLDOWN") then
      return CAT.CD
    end
    if t:find("BAD_TARGET") or t:find("NO_TARGET") or t:find("INVALID_TARGET") then
      return CAT.TARGET
    end
    if t:find("MOVING") then
      return CAT.MOVE
    end
    return CAT.OTHER
  end

  -- Otherwise try compare to known globalstring VALUES (localized).
  -- This is best-effort and safe if variables exist.
  local map = {
    [CAT.RANGE] = { "ERR_OUT_OF_RANGE", "SPELL_FAILED_OUT_OF_RANGE" },
    [CAT.LOS]   = { "SPELL_FAILED_LINE_OF_SIGHT", "SPELL_FAILED_NOT_INFRONT", "SPELL_FAILED_NOT_BEHIND" },
    [CAT.CD]    = { "SPELL_FAILED_NOT_READY", "ERR_ABILITY_COOLDOWN", "ERR_ITEM_COOLDOWN" },
    [CAT.TARGET]= { "ERR_INVALID_TARGET", "SPELL_FAILED_BAD_TARGETS", "SPELL_FAILED_TARGETS_DEAD", "ERR_NO_ATTACK_TARGET" },
    [CAT.RES]   = { "SPELL_FAILED_NO_POWER", "SPELL_FAILED_NO_MANA", "SPELL_FAILED_NO_ENERGY", "SPELL_FAILED_NO_RAGE" },
  }

  for cat, keys in pairs(map) do
    for i = 1, #keys do
      local v = _G[keys[i]]
      if type(v) == "string" and v == failedType then
        return cat
      end
    end
  end

  return CAT.OTHER
end

function F:Reset()
  self.seg = { total=0, RES=0, RNG=0, LOS=0, CD=0, TGT=0, MOV=0, OTH=0 }
  self.win = self.win or {}
  self.winHead = 1
  wipe_(self.win)

  self._lastRecordT = 0
  self._lastRecordCat = nil
end

function F:OnSegmentStart()
  self:Reset()
end

function F:OnSegmentEnd()
  -- keep data for HUD review after fight
end

function F:_Inc(cat)
  self.seg.total = self.seg.total + 1
  if cat == CAT.RES then self.seg.RES = self.seg.RES + 1
  elseif cat == CAT.RANGE then self.seg.RNG = self.seg.RNG + 1
  elseif cat == CAT.LOS then self.seg.LOS = self.seg.LOS + 1
  elseif cat == CAT.CD then self.seg.CD = self.seg.CD + 1
  elseif cat == CAT.TARGET then self.seg.TGT = self.seg.TGT + 1
  elseif cat == CAT.MOVE then self.seg.MOV = self.seg.MOV + 1
  else self.seg.OTH = self.seg.OTH + 1 end
end

function F:_RecordFailure(ts, cat)
  -- dedupe: UI_ERROR_MESSAGE and CLEU can fire almost same time
  if (ts - (self._lastRecordT or 0)) < 0.05 and self._lastRecordCat == cat then
    return
  end
  self._lastRecordT = ts
  self._lastRecordCat = cat

  self:_Inc(cat)
  local n = #self.win + 1
  self.win[n] = { t = ts, c = cat }
end

function F:_Prune(now, windowSec)
  local cutoff = now - windowSec
  local head = self.winHead or 1
  local w = self.win
  local n = #w
  while head <= n do
    local e = w[head]
    if e and e.t and e.t < cutoff then
      head = head + 1
    else
      break
    end
  end
  self.winHead = head

  -- compact occasionally
  if head > 256 then
    local new = {}
    local j = 1
    for i = head, n do
      new[j] = w[i]
      j = j + 1
    end
    self.win = new
    self.winHead = 1
  end
end

local function CountTop(tbl)
  local topCat, topN = CAT.OTHER, 0
  for k, v in pairs(tbl) do
    if k ~= "total" and type(v) == "number" and v > topN then
      topN = v
      topCat = k
    end
  end
  return topCat, topN
end

function F:GetWindowSummary(now, windowSec)
  if not self.win then return nil end
  now = now or Now()
  windowSec = windowSec or 60

  self:_Prune(now, windowSec)

  local c = { total=0, RES=0, RNG=0, LOS=0, CD=0, TGT=0, MOV=0, OTH=0 }
  local head = self.winHead or 1
  local w = self.win
  for i = head, #w do
    local e = w[i]
    if e and e.c then
      c.total = c.total + 1
      c[e.c] = (c[e.c] or 0) + 1
    end
  end

  local topCat, topN = CountTop(c)
  local resShare = (c.total > 0) and (c.RES / c.total) or 0
  local topShare = (c.total > 0) and (topN / c.total) or 0

  return {
    total = c.total,
    RES = c.RES, RNG = c.RNG, LOS = c.LOS, CD = c.CD, TGT = c.TGT, MOV = c.MOV, OTH = c.OTH,
    resShare = Clamp01(resShare),
    topCat = topCat,
    topShare = Clamp01(topShare),
  }
end

function F:GetSegmentSummary()
  local s = self.seg
  if not s then return nil end
  local total = s.total or 0
  local resShare = (total > 0) and ((s.RES or 0) / total) or 0
  local topCat, topN = CountTop(s)
  local topShare = (total > 0) and (topN / total) or 0
  return {
    total = total,
    RES = s.RES or 0, RNG = s.RNG or 0, LOS = s.LOS or 0, CD = s.CD or 0, TGT = s.TGT or 0, MOV = s.MOV or 0, OTH = s.OTH or 0,
    resShare = Clamp01(resShare),
    topCat = topCat,
    topShare = Clamp01(topShare),
  }
end

function F:Init()
  if self.frame then return end
  self:Reset()

  local f = CreateFrame("Frame")
  self.frame = f
  self.playerGUID = UnitGUID("player")

  f:RegisterEvent("PLAYER_LOGIN")
  -- In Midnight (12.0+), combat log events are removed from the Lua API.
  -- Registering them is pointless and may be noisy on some builds.
  local interface = select(4, GetBuildInfo())
  if type(interface) == "number" and interface < 120000 then
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  end
  f:RegisterEvent("UI_ERROR_MESSAGE")
  -- Some clients/builds may not have RegisterUnitEvent; keep resilient.
  if type(f.RegisterUnitEvent) == "function" then
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
  else
    f:RegisterEvent("UNIT_SPELLCAST_FAILED")
    f:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
  end

  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
      self.playerGUID = UnitGUID("player")
      return
    end

    if not IsSegmentActive() then
      return
    end

if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
  local unit, castGUID, spellID = ...
  if unit ~= "player" then return end

  -- In Midnight some GUIDs can be secret; do not compare/inspect them.
  if IsSecret(castGUID) then castGUID = nil end

  -- Defer categorization to UI_ERROR_MESSAGE if it arrives shortly after.
  self._pendingFailT = Now()
  self._pendingFail = true
  self._pendingFailId = (self._pendingFailId or 0) + 1
  local pid = self._pendingFailId

  C_Timer.After(0.15, function()
    if not self._pendingFail or self._pendingFailId ~= pid then return end
    if not IsSegmentActive() then return end
    self._pendingFail = false
    self:_RecordFailure(self._pendingFailT or Now(), CAT.OTHER)
  end)
  return
end

    if event == "UI_ERROR_MESSAGE" then
      local errorType, message = ...

      -- In Midnight instances, chat/error text can be Secret. Do not inspect it.
      if IsSecret(message) then
        -- Secret UI error: we must not inspect message contents. Count it as OTHER.
        self:_RecordFailure(Now(), CAT.OTHER)
        return
      end

      local stringId = nil
      if type(errorType) == "number" and GetGameMessageInfo then
        stringId = select(1, GetGameMessageInfo(errorType))
      end

      -- If stringId missing, attempt minimal matching by message against ERR_* values
      local cat = CatFromStringId(stringId)

      -- If still OTHER and message exists, compare to a couple of common constants
      if cat == CAT.OTHER and type(message) == "string" then
        if type(ERR_OUT_OF_RANGE) == "string" and message == ERR_OUT_OF_RANGE then
          cat = CAT.RANGE
        elseif type(ERR_BADATTACKPOS) == "string" and message == ERR_BADATTACKPOS then
          cat = CAT.LOS
        end
      end

local now = Now()

-- If a cast failed event fired, UI_ERROR_MESSAGE usually follows. Use it to categorize.
if self._pendingFail and self._pendingFailT and (now - self._pendingFailT) < 0.25 then
  self._pendingFail = false
  self:_RecordFailure(now, cat)
  return
end

self:_RecordFailure(now, cat)
return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      local _, subevent, _, sourceGUID = CombatLogGetCurrentEventInfo()
      if subevent ~= "SPELL_CAST_FAILED" then return end
      if not sourceGUID or sourceGUID ~= self.playerGUID then return end

      local spellId, spellName, spellSchool, failedType = select(12, CombatLogGetCurrentEventInfo())
      local cat = CatFromFailedType(failedType)

      -- Only record if it looks meaningful; otherwise UI_ERROR_MESSAGE usually covers it.
      -- Still keep it for clients that suppress UI errors.
      self:_RecordFailure(Now(), cat)
      return
    end
  end)
end
