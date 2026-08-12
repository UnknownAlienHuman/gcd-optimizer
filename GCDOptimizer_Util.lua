-- GCDOptimizer_Util.lua
-- Small utilities: clamp, deque, stats helpers

local _, NS = ...

NS.Util = NS.Util or {}
local U = NS.Util

function U.Clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

-- ----------------------------
-- Deque (array + head index)
-- pushBack, popFrontWhile, iterate
-- ----------------------------
U.Deque = {}
U.Deque.__index = U.Deque

-- Compact internal storage occasionally to avoid unbounded growth of array indices.
-- This is important for long sessions where we popFront frequently (sliding windows).
function U.Deque:MaybeCompact()
  local head, tail = self.head, self.tail
  -- Only consider compacting when head advanced far.
  if head <= 1024 then return end

  local size = tail - head + 1
  if size <= 0 then
    self.data = {}
    self.head = 1
    self.tail = 0
    return
  end

  -- Compact when the "wasted" prefix is much larger than the live size.
  -- This keeps indices small and reduces GC pressure.
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
  return (self.tail - self.head + 1)
end

function U.Deque:PushBack(v)
  local t = self.tail + 1
  self.tail = t
  self.data[t] = v
end

function U.Deque:Front()
  if self.head > self.tail then return nil end
  return self.data[self.head]
end

function U.Deque:PopFront()
  if self.head > self.tail then return nil end
  local v = self.data[self.head]
  self.data[self.head] = nil
  self.head = self.head + 1
  self:MaybeCompact()
  return v
end

function U.Deque:PopFrontWhile(pred)
  while true do
    local v = self:Front()
    if not v then return end
    if not pred(v) then return end
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
-- Stats: mean / median / percentile
-- (for small N like 20-100; copy+sort is fine)
-- ----------------------------
local function copyAndSort(arr)
  local tmp = {}
  for i = 1, #arr do tmp[i] = arr[i] end
  table.sort(tmp)
  return tmp
end

function U.Mean(arr)
  local n = #arr
  if n == 0 then return 0 end
  local s = 0
  for i = 1, n do s = s + arr[i] end
  return s / n
end

function U.Median(arr)
  local n = #arr
  if n == 0 then return 0 end
  local s = copyAndSort(arr)
  local mid = math.floor((n + 1) / 2)
  if (n % 2) == 1 then
    return s[mid]
  else
    return (s[mid] + s[mid + 1]) / 2
  end
end

function U.Percentile(arr, p) -- p in [0,1]
  local n = #arr
  if n == 0 then return 0 end
  local s = copyAndSort(arr)
  local idx = math.floor(U.Clamp(p, 0, 1) * (n - 1) + 1)
  return s[idx]
end
