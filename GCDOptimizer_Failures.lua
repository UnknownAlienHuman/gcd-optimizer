-- GCDOptimizer_Failures.lua
-- Secret-safe failure counter for Retail 12.1.
--
-- The module intentionally ignores event payloads and does not parse
-- UI error text, combat-log data, spell IDs, targets, resources, or text.
-- It can therefore report the frequency of failed cast attempts, but not infer
-- a specific failure reason from restricted state.

local _, NS = ...

NS.Failures = NS.Failures or {}
local F = NS.Failures

local CATEGORY_KEYS = { "RES", "RNG", "LOS", "CD", "TGT", "MOV", "OTH" }

local function NewCounts()
  return {
    total = 0,
    RES = 0,
    RNG = 0,
    LOS = 0,
    CD = 0,
    TGT = 0,
    MOV = 0,
    OTH = 0,
  }
end

local function BuildSummary(counts)
  local total = counts.total or 0
  local topCategory = "OTH"
  local topCount = counts.OTH or 0

  for _, category in ipairs(CATEGORY_KEYS) do
    local value = counts[category] or 0
    if value > topCount then
      topCategory = category
      topCount = value
    end
  end

  return {
    total = total,
    RES = counts.RES or 0,
    RNG = counts.RNG or 0,
    LOS = counts.LOS or 0,
    CD = counts.CD or 0,
    TGT = counts.TGT or 0,
    MOV = counts.MOV or 0,
    OTH = counts.OTH or 0,
    topCat = topCategory,
    topShare = total > 0 and (topCount / total) or 0,
    resShare = total > 0 and ((counts.RES or 0) / total) or 0,
  }
end

function F:Reset()
  self.inSegment = false
  self.segmentCounts = NewCounts()
  self.events = {}
  self.eventHead = 1
  self.lastFailureAt = 0
end

function F:_RecordFailure(now)
  if not self.inSegment then return end

  local last = self.lastFailureAt or 0
  if last > 0 and (now - last) < 0.05 then
    return
  end
  self.lastFailureAt = now

  local counts = self.segmentCounts
  counts.total = counts.total + 1
  counts.OTH = counts.OTH + 1
  self.events[#self.events + 1] = now

  local cutoff = now - 120
  local head = self.eventHead or 1
  while head <= #self.events and self.events[head] < cutoff do
    head = head + 1
  end
  self.eventHead = head

  if head > 512 and head > (#self.events / 2) then
    local compact = {}
    for i = head, #self.events do
      compact[#compact + 1] = self.events[i]
    end
    self.events = compact
    self.eventHead = 1
  end
end

function F:Init()
  if self._inited then return end
  self._inited = true
  self:Reset()

  local frame = CreateFrame("Frame")
  self.frame = frame
  frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
  frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
  frame:SetScript("OnEvent", function()
    self:_RecordFailure(GetTime())
  end)
end

function F:OnSegmentStart()
  self.segmentCounts = NewCounts()
  self.events = {}
  self.eventHead = 1
  self.lastFailureAt = 0
  self.inSegment = true
end

function F:OnSegmentEnd()
  self.inSegment = false
end

function F:GetSegmentSummary()
  return BuildSummary(self.segmentCounts or NewCounts())
end

function F:GetWindowSummary(now, windowSeconds)
  now = now or GetTime()
  windowSeconds = windowSeconds or 5
  local cutoff = now - windowSeconds
  local total = 0

  for i = self.eventHead or 1, #(self.events or {}) do
    local timestamp = self.events[i]
    if timestamp >= cutoff and timestamp <= now then
      total = total + 1
    end
  end

  local counts = NewCounts()
  counts.total = total
  counts.OTH = total
  return BuildSummary(counts)
end
