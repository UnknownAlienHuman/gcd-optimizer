-- GCDOptimizer_Util.lua
-- Shared numeric helpers, bounded deque/statistics, and the single
-- Secret-aware boundary for GCD and attack-speed observations.

local _, NS = ...

NS.Util = NS.Util or {}
local U = NS.Util

U.GCD_SPELL_ID = 61304

U.GCD_STATUS_EXACT = "DIRECT_EXACT"
U.GCD_STATUS_ACTIVE_RESTRICTED = "ACTIVE_RESTRICTED"
U.GCD_STATUS_INACTIVE = "INACTIVE"
U.GCD_STATUS_UNAVAILABLE = "UNAVAILABLE"
U.GCD_STATUS_MALFORMED = "MALFORMED"

U.GCD_SOURCE_DIRECT = "DIRECT_EXACT"
U.GCD_SOURCE_ESTIMATED = "ESTIMATED_SWING"
U.GCD_SOURCE_CACHED = "CACHED_LOW_CONFIDENCE"

function U.Clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

function U.IsFiniteNumber(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
end

-- Gate Secret-capable values before every Lua operation that consumes them.
function U.CanAccessValues(...)
  if type(canaccessallvalues) == "function" then
    return canaccessallvalues(...)
  end

  local count = select("#", ...)
  if type(canaccessvalue) == "function" then
    for index = 1, count do
      if not canaccessvalue(select(index, ...)) then
        return false
      end
    end
    return true
  end

  if type(issecretvalue) == "function" then
    for index = 1, count do
      if issecretvalue(select(index, ...)) then
        return false
      end
    end
  end

  return true
end

function U.CanAccessTable(value)
  if not U.CanAccessValues(value) then return false end
  if type(value) ~= "table" then return false end
  if type(canaccesstable) == "function" and not canaccesstable(value) then
    return false
  end
  return true
end

local function ReadField(info, key)
  -- pcall contains a denied field access; it does not declassify the value.
  local ok, value = pcall(function() return info[key] end)
  if not ok or not U.CanAccessValues(value) then
    return false, nil
  end
  return true, value
end

-- Returns:
--   status, startTime, wallDuration, rawDuration, modRate
-- Numeric timing is returned only for DIRECT_EXACT. isActive is NeverSecret in
-- the selected generated contract and lets the detector reject off-GCD success
-- events even when the numerical fields are restricted.
function U.ReadGCDObservation()
  if type(C_Spell) ~= "table" or type(C_Spell.GetSpellCooldown) ~= "function" then
    return U.GCD_STATUS_UNAVAILABLE
  end

  local ok, info = pcall(C_Spell.GetSpellCooldown, U.GCD_SPELL_ID)
  if not ok then
    return U.GCD_STATUS_UNAVAILABLE
  end
  if not U.CanAccessTable(info) then
    return U.GCD_STATUS_UNAVAILABLE
  end

  local activeReadable, isActive = ReadField(info, "isActive")
  if activeReadable then
    if type(isActive) ~= "boolean" then
      return U.GCD_STATUS_MALFORMED
    end
    if not isActive then
      return U.GCD_STATUS_INACTIVE
    end
  end

  local startReadable, startTime = ReadField(info, "startTime")
  local durationReadable, rawDuration = ReadField(info, "duration")
  local rateReadable, modRate = ReadField(info, "modRate")
  if not (startReadable and durationReadable and rateReadable) then
    return activeReadable and U.GCD_STATUS_ACTIVE_RESTRICTED or U.GCD_STATUS_UNAVAILABLE
  end

  if not U.IsFiniteNumber(startTime)
    or not U.IsFiniteNumber(rawDuration)
    or not U.IsFiniteNumber(modRate)
    or startTime <= 0
    or rawDuration <= 0
    or modRate <= 0
  then
    return U.GCD_STATUS_MALFORMED
  end

  local wallDuration = rawDuration / modRate
  if not U.IsFiniteNumber(wallDuration) or wallDuration <= 0 then
    return U.GCD_STATUS_MALFORMED
  end

  return U.GCD_STATUS_EXACT, startTime, wallDuration, rawDuration, modRate
end

-- Compatibility helper for callers that only need exact ordinary timing.
function U.ReadGCDCooldown()
  local status, startTime, duration = U.ReadGCDObservation()
  if status ~= U.GCD_STATUS_EXACT then return nil, nil end
  return startTime, duration
end

function U.ReadPlayerAttackSpeed()
  if type(UnitAttackSpeed) ~= "function" then return nil end

  local ok, mainHand = pcall(UnitAttackSpeed, "player")
  if not ok or not U.CanAccessValues(mainHand) then return nil end
  if not U.IsFiniteNumber(mainHand) or mainHand <= 0 then return nil end
  return mainHand
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
    local compact = {}
    local target = 1
    for index = head, tail do
      compact[target] = self.data[index]
      target = target + 1
    end
    self.data = compact
    self.head = 1
    self.tail = target - 1
  end
end

function U.Deque:New()
  return setmetatable({ data = {}, head = 1, tail = 0 }, self)
end

function U.Deque:Size()
  return self.tail - self.head + 1
end

function U.Deque:PushBack(value)
  self.tail = self.tail + 1
  self.data[self.tail] = value
end

function U.Deque:Back()
  if self.head > self.tail then return nil end
  return self.data[self.tail]
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
  local index = self.head - 1
  return function()
    index = index + 1
    if index <= self.tail then
      return self.data[index]
    end
  end
end

-- ----------------------------
-- Statistics for small samples
-- ----------------------------
local function CopyAndSort(values)
  local copy = {}
  for index = 1, #values do copy[index] = values[index] end
  table.sort(copy)
  return copy
end

function U.Mean(values)
  local count = #values
  if count == 0 then return 0 end
  local total = 0
  for index = 1, count do total = total + values[index] end
  return total / count
end

function U.Median(values)
  local count = #values
  if count == 0 then return 0 end
  local sorted = CopyAndSort(values)
  local middle = math.floor((count + 1) / 2)
  if (count % 2) == 1 then return sorted[middle] end
  return (sorted[middle] + sorted[middle + 1]) / 2
end

function U.Percentile(values, percentile)
  local count = #values
  if count == 0 then return 0 end
  local sorted = CopyAndSort(values)
  local index = math.floor(U.Clamp(percentile, 0, 1) * (count - 1) + 1)
  return sorted[index]
end
