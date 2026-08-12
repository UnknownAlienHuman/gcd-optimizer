-- GCDOptimizer_Test.lua
-- Lightweight in-game test harness (manual, out-of-combat recommended).
--
-- Goals:
--  - Ensure our Midnight-safe code paths never do arithmetic on Secret values.
--  - Provide deterministic simulation of the GCDEstimator logic.
--
-- Usage:
--  /gcdopt test
--  /gcdopt debug
--  /gcdopt anchors   (prints last ~30 anchor events)
--
local _, NS = ...
local U = NS.Util

NS.Test = NS.Test or {}
local T = NS.Test

local function Print(...)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGCDOpt|r "..table.concat({tostringall(...)}, " "))
  end
end

-- --------- pure-Lua simulation (no WoW APIs) ----------
local function SimulateEstimator()
  local E = NS.GCDEstimator
  if not E then
    Print("Estimator missing")
    return
  end

  -- Snapshot real settings, then monkey-patch minimal methods.
  local realGetTime = GetTime
  local t = 0

  -- Simple timeline helper
  local function Step(dt)
    t = t + dt
  end

  -- Override GetTime() for the simulation.
  _G.GetTime = function() return t end

  -- Monkey-patch internal helpers by overriding public getters:
  -- We can't reach locals inside module, so we test via externally visible behavior:
  -- set baselines directly.
  E:Reset()
  E.baseGCD = 1.5
  E.baseSwing = 2.6 -- e.g. slow 2H weapon baseline
  E.lastPred = 1.5

  -- Simulate haste: swing goes to 2.0 => hasteMult=1.3 => gcd ~ 1.15
  local swings = { 2.0, 2.0, 1.8, 2.2, 2.0 }
  local i = 1

  -- Stub UnitAttackSpeed for simulation
  local realUAS = UnitAttackSpeed
  _G.UnitAttackSpeed = function()
    return swings[i] or 2.0
  end

  -- Stub cooldown read path: force "unreadable"
  local realGetSpellCooldown = GetSpellCooldown
  _G.GetSpellCooldown = function() return 0, 0 end
  if C_Spell and C_Spell.GetSpellCooldown then
    -- leave as-is; our ReadGCDCooldown will treat missing/0 as nil
  end

  local preds = {}
  for k = 1, #swings do
    i = k
    preds[#preds + 1] = E:GetPredictedGCD()
    Step(0.10)
  end

  -- Restore
  _G.UnitAttackSpeed = realUAS
  _G.GetSpellCooldown = realGetSpellCooldown
  _G.GetTime = realGetTime

  return preds
end

function T:Run()
  local preds = SimulateEstimator()
  if not preds then return end

  local s = {}
  for i = 1, #preds do
    s[#s + 1] = string.format("%.3f", preds[i])
  end

  Print("Test predicted GCD series:", table.concat(s, ", "))
  Print("Expected: values ~1.15s with mild variation from swing ratio.")
end

function T:Debug()
  if not NS.GCDEstimator then
    Print("Estimator missing")
    return
  end
  local snap = NS.GCDEstimator:DebugSnapshot()
  Print("Estimator:", "baseGCD="..tostring(snap.baseGCD), "baseSwing="..tostring(snap.baseSwing), "lastPred="..tostring(snap.lastPred), "obsEWMA="..tostring(snap.obsEWMA))
end

-- --------- slash command ----------
SLASH_GCDOPT1 = "/gcdopt"
SlashCmdList.GCDOPT = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "test" then
    T:Run()
  elseif msg == "debug" then
    T:Debug()
  elseif msg == "anchors" then
    T:Anchors()
  else
    Print("Commands: /gcdopt test | /gcdopt debug | /gcdopt anchors")
  end
end
function T:Anchors()
  if not (NS.Anchors and NS.Anchors.GetRecentEvents) then
    Print("Anchors module not available.")
    return
  end
  local ev = NS.Anchors:GetRecentEvents() or {}
  -- print last ~30 events (ring buffer order is not strictly chronological in storage)
  local out = {}
  for i = 1, #ev do
    if ev[i] then table.insert(out, ev[i]) end
  end
  table.sort(out, function(a,b) return (a.t or 0) < (b.t or 0) end)
  local start = math.max(1, #out - 29)
  for i = start, #out do
    local e = out[i]
    local line = string.format("[%.3f] %s", e.t or 0, e.type or "?")
    if e.overlaySpellID then line = line .. " overlay=" .. tostring(e.overlaySpellID) end
    if e.matchedSpellID then line = line .. " used=" .. tostring(e.matchedSpellID) end
    if e.confidence then line = line .. string.format(" conf=%.2f", e.confidence) end
    if e.reason then line = line .. " (" .. tostring(e.reason) .. ")" end
    Print(line)
  end
end

