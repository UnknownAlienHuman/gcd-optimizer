-- GCDOptimizer_Anchors.lua
-- Anchor system: tries to infer "server accepted / proc consumed" using only UI-layer signals.
--
-- Motivation (Midnight):
-- * Many classic confirmations (CLEU, unit aura details, cooldown math) may be hidden as Secret Values in combat.
-- * We therefore build a *multi-signal* anchoring layer that:
--   - never assumes values are accessible;
--   - records evidence with confidence scores;
--   - degrades gracefully when some signals are unavailable.
--
-- Primary anchor strategy requested:
--   "Proc consumed" ~= overlay glow disappears shortly after a player action.
--   We DO NOT anchor on proc appearance (glow show) because it can happen passively (e.g., auto attacks).
--
-- What we record:
--   - Overlay glow show/hide (spell activation overlay)
--   - Cast attempt (UNIT_SPELLCAST_SENT) and cast success (UNIT_SPELLCAST_SUCCEEDED)
--   - Recent local presses (from Metrics.pressQueue) if available
--
-- Important:
--   Overlay glow hide is not a guaranteed 'consumption' signal:
--     - proc can expire,
--     - UI can hide overlay on context changes,
--     - overlay can be shared by multiple spells.
--   We therefore correlate hide with *nearby cast success* of allowed consumer spells.

local _, NS = ...
NS.Anchors = NS.Anchors or {}
local A = NS.Anchors

local function Now() return GetTime() end

-- ---------- defaults / schema ----------
-- Stored in SavedVariables (GCDOptimizerDB.anchors)
-- NOTE: keep this schema stable; add fields only.
local DEFAULTS = {
  enabled = true,

  -- time window (seconds) to correlate overlay fade with an action
  fadeWindow = 0.25,

  -- additional window to search for cast success (allow latency)
  successWindow = 0.40,

  -- How long to keep recent cast history (seconds)
  castHistorySeconds = 2.0,

  -- ring buffer sizes (debug)
  maxEvents = 600,

  -- rules: keys are "overlaySpellID" that appears in SPELL_ACTIVATION_OVERLAY_* events.
  -- Each rule defines which "consumer spells" can plausibly spend that proc.
  -- Keep empty by default: you will populate per-class/spec after in-game verification.
  rules = {
    -- Example template (DISABLED by default; spellIDs are placeholders; verify before enabling):
    -- [12345] = {
    --   name = "ProcName",
    --   consume = { 11111, 22222 }, -- spellIDs that spend the proc
    --   requireSucceeded = true,    -- true => need UNIT_SPELLCAST_SUCCEEDED match; false => allow press-only match
    -- },
  },
}

-- ---------- internal state ----------
A._inited = A._inited or false
A._frame = A._frame or nil

A._activeOverlays = A._activeOverlays or {} -- [overlaySpellID] = { shownAt, lastState=true/false }
A._recentCasts = A._recentCasts or {}       -- array of { t, spellID, guid, kind="sent"/"succeeded" }

A._events = A._events or {}                 -- ring buffer of debug records
A._eventHead = A._eventHead or 0

local function GetCfg()
  local db = NS:GetConfig()
  db.anchors = db.anchors or {}
  -- deep-ish merge (only one level + rules table)
  for k, v in pairs(DEFAULTS) do
    if db.anchors[k] == nil then
      if type(v) == "table" then
        db.anchors[k] = {}
      else
        db.anchors[k] = v
      end
    end
  end
  db.anchors.rules = db.anchors.rules or {}
  return db.anchors
end

local function PushEvent(e)
  local cfg = GetCfg()
  local maxN = cfg.maxEvents or DEFAULTS.maxEvents
  A._eventHead = (A._eventHead or 0) + 1
  local idx = ((A._eventHead - 1) % maxN) + 1
  A._events[idx] = e
end

-- Return the most recent press in the window. Optionally filter by kind/id.
local function FindRecentPress(now, window, kind, id)
  if not (NS.Metrics and NS.Metrics.pressQueue and NS.Metrics.pressQueue.data) then return nil end
  local dq = NS.Metrics.pressQueue
  local data = dq.data
  local head, tail = dq.head, dq.tail
  for i = tail, head, -1 do
    local p = data[i]
    if not p then break end
    if (now - p.t) > window then break end
    if (not kind or p.kind == kind) and (id == nil or p.id == id) then
      return p
    end
  end
  return nil
end

local function PruneCasts(now, keepSec)
  keepSec = keepSec or 2.0
  local out = A._recentCasts
  local n = #out
  if n == 0 then return end
  local j = 1
  for i = 1, n do
    if out[i].t >= (now - keepSec) then
      out[j] = out[i]
      j = j + 1
    end
  end
  for k = j, n do out[k] = nil end
end

local function RecordCast(kind, guid, spellID)
  local now = Now()
  local cfg = GetCfg()
  table.insert(A._recentCasts, { t = now, kind = kind, guid = guid, spellID = spellID })
  PruneCasts(now, cfg.castHistorySeconds or DEFAULTS.castHistorySeconds)
end

local function FindRecentCastSucceeded(now, window, consumeSet)
  -- consumeSet: table[spellID]=true or nil to accept any
  window = window or 0.40
  local casts = A._recentCasts
  for i = #casts, 1, -1 do
    local c = casts[i]
    if (now - c.t) > window then break end
    if c.kind == "succeeded" then
      if not consumeSet or consumeSet[c.spellID] then
        return c
      end
    end
  end
  return nil
end

local function BuildConsumeSet(rule)
  if not (rule and rule.consume) then return nil end
  local set = {}
  for _, sid in ipairs(rule.consume) do
    set[sid] = true
  end
  return set
end

-- ---------- overlay fade correlation ----------
local function OnOverlayShow(overlaySpellID)
  local now = Now()
  A._activeOverlays[overlaySpellID] = A._activeOverlays[overlaySpellID] or {}
  local st = A._activeOverlays[overlaySpellID]
  st.shownAt = now
  st.lastState = true

  PushEvent({
    t = now,
    type = "overlay_show",
    overlaySpellID = overlaySpellID,
  })
end

local function OnOverlayHide(overlaySpellID)
  local now = Now()
  local cfg = GetCfg()
  local rule = cfg.rules and cfg.rules[overlaySpellID] or nil

  -- Mark hidden
  A._activeOverlays[overlaySpellID] = A._activeOverlays[overlaySpellID] or {}
  local st = A._activeOverlays[overlaySpellID]
  st.hiddenAt = now
  st.lastState = false

  local fadeWin = cfg.fadeWindow or DEFAULTS.fadeWindow
  local succWin = cfg.successWindow or DEFAULTS.successWindow

  local consumeSet = BuildConsumeSet(rule)
  local cast = FindRecentCastSucceeded(now, succWin, consumeSet)

  local press = FindRecentPress(now, fadeWin, nil, nil)

  local confidence = 0.0
  local matchedSpellID = nil
  local reason = "unknown"

  if cast then
    confidence = 0.90
    matchedSpellID = cast.spellID
    reason = "overlay_hide + cast_succeeded"
  elseif press and rule and rule.requireSucceeded == false then
    confidence = 0.55
    reason = "overlay_hide + local_press"
  elseif press then
    confidence = 0.35
    reason = "overlay_hide + local_press (no success match)"
  else
    confidence = 0.15
    reason = "overlay_hide (no nearby action)"
  end

  PushEvent({
    t = now,
    type = "overlay_fade",
    overlaySpellID = overlaySpellID,
    procName = rule and rule.name or nil,
    matchedSpellID = matchedSpellID,
    confidence = confidence,
    reason = reason,
  })

  -- Optional: expose a hook to other modules
  if type(A.OnAnchorEvent) == "function" then
    pcall(A.OnAnchorEvent, A, overlaySpellID, matchedSpellID, confidence, reason, now)
  end
end

-- ---------- event frame ----------
function A:Init()
  if self._inited then return end
  self._inited = true

  local cfg = GetCfg()
  if not cfg.enabled then return end

  local f = CreateFrame("Frame")
  self._frame = f

  -- Overlay events
  f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
  -- Some clients also fire SHOW/HIDE; we try to listen if present.
  f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
  f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")

  -- Cast events (player)
  f:RegisterEvent("UNIT_SPELLCAST_SENT")
  f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  f:RegisterEvent("UNIT_SPELLCAST_FAILED")
  f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

  f:SetScript("OnEvent", function(_, event, ...)
    if not (NS.state and NS.state.inSegment) then
      -- still allow baseline overlay/cast history outside segment? no, keep clean.
      return
    end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
      local spellID = ...
      if type(spellID) == "number" then
        OnOverlayShow(spellID)
      end

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
      local spellID = ...
      if type(spellID) == "number" then
        OnOverlayHide(spellID)
      end

    elseif event == "SPELL_ACTIVATION_OVERLAY_SHOW" then
      local spellID = ...
      if type(spellID) == "number" then
        OnOverlayShow(spellID)
      end

    elseif event == "SPELL_ACTIVATION_OVERLAY_HIDE" then
      local spellID = ...
      if type(spellID) == "number" then
        OnOverlayHide(spellID)
      end

    elseif event == "UNIT_SPELLCAST_SENT" then
      local unit, target, castGUID, spellID = ...
      if unit == "player" then
        if type(spellID) == "number" then
          RecordCast("sent", castGUID, spellID)
        end
      end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      local unit, castGUID, spellID = ...
      if unit == "player" then
        if type(spellID) == "number" then
          RecordCast("succeeded", castGUID, spellID)
        end
      end

    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
      local unit, castGUID, spellID = ...
      if unit == "player" then
        PushEvent({
          t = Now(),
          type = (event == "UNIT_SPELLCAST_FAILED") and "cast_failed" or "cast_interrupted",
          spellID = spellID,
          guid = castGUID,
        })
      end
    end
  end)
end

function A:Reset(now)
  now = now or Now()
  self._activeOverlays = {}
  self._recentCasts = {}
  self._events = {}
  self._eventHead = 0
  PushEvent({ t = now, type = "anchors_reset" })
end

function A:OnSegmentStart(now)
  self:Reset(now)
end

function A:OnSegmentEnd(now)
  -- keep ring buffer for after-action inspection; do not clear.
  PushEvent({ t = now or Now(), type = "segment_stop" })
end

-- Debug export (safe)
function A:GetRecentEvents()
  return self._events
end

-- Backwards/compat naming
function A:OnSegmentStop(now)
  return self:OnSegmentEnd(now)
end
