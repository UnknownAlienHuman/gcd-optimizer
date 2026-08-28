-- GCDOptimizer_Anchors.lua
-- Optional diagnostic correlation between accessible spell-overlay fades and
-- ordinary local press timestamps. No cast GUID, target, aura, or combat-log
-- payload is retained.

local _, NS = ...
local U = NS.Util

NS.Anchors = NS.Anchors or {}
local A = NS.Anchors

local DEFAULTS = {
  enabled = true,
  fadeWindow = 0.25,
  maxEvents = 300,
  rules = {},
}

local function Now()
  return GetTime()
end

local function GetCfg()
  local db = NS:GetConfig()
  if type(db.anchors) ~= "table" then db.anchors = {} end
  for key, value in pairs(DEFAULTS) do
    if db.anchors[key] == nil then
      db.anchors[key] = type(value) == "table" and {} or value
    end
  end
  if type(db.anchors.rules) ~= "table" then db.anchors.rules = {} end
  return db.anchors
end

local function MaxEvents(cfg)
  local value = tonumber(cfg.maxEvents) or DEFAULTS.maxEvents
  return U.Clamp(math.floor(value), 50, 2000)
end

local function PushEvent(eventData)
  local maxEvents = MaxEvents(GetCfg())
  A._eventHead = (A._eventHead or 0) + 1
  local index = ((A._eventHead - 1) % maxEvents) + 1
  A._events[index] = eventData
end

local function FindRecentPress(now, window)
  local metrics = NS.Metrics
  local queue = metrics and metrics.pressQueue
  if not (queue and queue.data) then return nil end

  for i = queue.tail or 0, queue.head or 1, -1 do
    local press = queue.data[i]
    if press and type(press.t) == "number" then
      local age = now - press.t
      if age > window then return nil end
      if age >= 0 then return press end
    end
  end
  return nil
end

local function RuleName(cfg, spellID)
  local rule = cfg.rules[spellID]
  if type(rule) == "table" and type(rule.name) == "string" then
    return rule.name
  end
  return nil
end

local function OnOverlayShow(spellID)
  local now = Now()
  local cfg = GetCfg()
  A._activeOverlays[spellID] = now
  PushEvent({
    t = now,
    type = "overlay_show",
    overlaySpellID = spellID,
    procName = RuleName(cfg, spellID),
  })
end

local function OnOverlayHide(spellID)
  local now = Now()
  local cfg = GetCfg()
  local shownAt = A._activeOverlays[spellID]
  A._activeOverlays[spellID] = nil

  local fadeWindow = tonumber(cfg.fadeWindow) or DEFAULTS.fadeWindow
  fadeWindow = U.Clamp(fadeWindow, 0.05, 1.00)
  local press = FindRecentPress(now, fadeWindow)

  PushEvent({
    t = now,
    type = "overlay_hide",
    overlaySpellID = spellID,
    procName = RuleName(cfg, spellID),
    shownFor = type(shownAt) == "number" and math.max(0, now - shownAt) or nil,
    confidence = press and 0.45 or 0.10,
    reason = press and "overlay_hide + local_press" or "overlay_hide",
  })
end

function A:Init()
  if self._inited then return end
  self._inited = true
  self._events = self._events or {}
  self._activeOverlays = self._activeOverlays or {}
  self._eventHead = self._eventHead or 0

  local cfg = GetCfg()
  if not cfg.enabled then return end

  local frame = CreateFrame("Frame")
  self._frame = frame
  frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
  frame:SetScript("OnEvent", function(_, event, spellID)
    if not (NS.state and NS.state.inSegment) then return end
    if not U.CanAccessValues(spellID) then return end
    if type(spellID) ~= "number" or spellID <= 0 then return end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
      OnOverlayShow(spellID)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
      OnOverlayHide(spellID)
    end
  end)
end

function A:Reset(now)
  self._activeOverlays = {}
  self._events = {}
  self._eventHead = 0
  PushEvent({ t = now or Now(), type = "anchors_reset" })
end

function A:OnSegmentStart(now)
  self:Reset(now)
end

function A:OnSegmentEnd(now)
  PushEvent({ t = now or Now(), type = "segment_stop" })
end

function A:OnSegmentStop(now)
  return self:OnSegmentEnd(now)
end

function A:GetRecentEvents()
  local cfg = GetCfg()
  local maxEvents = MaxEvents(cfg)
  local head = self._eventHead or 0
  local first = math.max(1, head - maxEvents + 1)
  local output = {}

  for sequence = first, head do
    local index = ((sequence - 1) % maxEvents) + 1
    local eventData = self._events[index]
    if eventData then output[#output + 1] = eventData end
  end

  return output
end
