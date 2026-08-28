-- GCDOptimizer_Util.lua
-- Shared helpers, bounded deque, statistics, and the Secret-safe cooldown boundary.

local _, NS = ...

NS.Util = NS.Util or {}
local U = NS.Util

U.GCD_SPELL_ID = 61304

function U.Clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

-- Test accessibility before any branch, comparison, arithmetic, formatting,
-- indexing, or persistence of a value returned by a Secret-capable API.
function U.CanAccessValues(...)
  if type(canaccessallvalues) == "function" then
    return canaccessallvalues(...)
  end

  local count = select("#", ...)
  if type(canaccessvalue) == "function" then
    for i = 1, count do
      if not canaccessvalue(select(i, ...)) then
        return false
      end
    end
    return true
  end

  if type(issecretvalue) == "function" then
    for i = 1, count do
      if issecretvalue(select(i, ...)) then
        return false
      end
    end
  end

  return true
end

-- Returns ordinary numeric startTime/duration values only. Inaccessible,
-- missing, inactive, and malformed cooldowns all collapse to nil, nil.
function U.ReadSpellCooldown(spellID)
  if type(spellID) ~= "number" or spellID <= 0 then
    return nil, nil
  end
  if type(C_Spell) ~= "table" or type(C_Spell.GetSpellCooldown) ~= "function" then
    return nil, nil
  end

  local info = C_Spell.GetSpellCooldown(spellID)
  if not U.CanAccessValues(info) then
    return nil, nil
  end
  if type(info) ~= "table" then
    return nil, nil
  end

  local startTime = info.startTime
  local duration = info.duration
  if not U.CanAccessValues(startTime, duration) then
    return nil, nil
  end
  if type(startTime) ~= "number" or type(duration) ~= "number" then
    return nil, nil
  end
  if startTime <= 0 or duration <= 0 then
    return nil, nil
  end

  return startTime, duration
end

function U.ReadGCDCooldown()
  return U.ReadSpellCooldown(U.GCD_SPELL_ID)
end

-- ----------------------------
-- Deque (array + head index)
-- ----------------------------
U.Deque = {}
U.Deque.__index = U.Deque

function U.Deque:MaybeCompact()
  local head, tail = self.head, self.tail
  if head <= 1024 then return end

  local size = tail - head + 1
  if size <= 0 then
    self.data = {}
    self.head = 1
    self.tail = 0
    return
  end

  if head > (size * 2) then
    local new = {}
    local j = 1
    for i = head, tail do
      new[j] = self.data[i]
      j = j + 1
    end
    self.data = new
    self.head = 1
    self.tail = j - 1
  end
end

function U.Deque:New()
  return setmetatable({ data = {}, head = 1, tail = 0 }, self)
end

function U.Deque:Size()
  return self.tail - self.head + 1
end

function U.Deque:PushBack(v)
  local tail = self.tail + 1
  self.tail = tail
  self.data[tail] = v
end

function U.Deque:Front()
  if self.head > self.tail then return nil end
  return self.data[self.head]
end

function U.Deque:PopFront()
  if self.head > self.tail then return nil end
  local value = self.data[self.head]
  self.data[self.head] = nil
  self.head = self.head + 1
  self:MaybeCompact()
  return value
end

function U.Deque:PopFrontWhile(predicate)
  while true do
    local value = self:Front()
    if value == nil or not predicate(value) then return end
    self:PopFront()
  end
end

function U.Deque:Iter()
  local i = self.head - 1
  return function()
    i = i + 1
    if i <= self.tail then
      return self.data[i]
    end
  end
end

-- ----------------------------
-- Statistics for small samples
-- ----------------------------
local function CopyAndSort(values)
  local copy = {}
  for i = 1, #values do copy[i] = values[i] end
  table.sort(copy)
  return copy
end

function U.Mean(values)
  local count = #values
  if count == 0 then return 0 end
  local total = 0
  for i = 1, count do total = total + values[i] end
  return total / count
end

function U.Median(values)
  local count = #values
  if count == 0 then return 0 end
  local sorted = CopyAndSort(values)
  local mid = math.floor((count + 1) / 2)
  if (count % 2) == 1 then
    return sorted[mid]
  end
  return (sorted[mid] + sorted[mid + 1]) / 2
end

function U.Percentile(values, percentile)
  local count = #values
  if count == 0 then return 0 end
  local sorted = CopyAndSort(values)
  local index = math.floor(U.Clamp(percentile, 0, 1) * (count - 1) + 1)
  return sorted[index]
end
