-- GCDOptimizer_PressTracker.lua
-- Records only local press timestamps. Hook arguments are deliberately ignored
-- so spell names, spell IDs, macro text, action payloads, and target data never
-- cross into metrics state.

local _, NS = ...

NS.PressTracker = NS.PressTracker or {}
local P = NS.PressTracker

local function RecordPress()
  if not (NS.state and NS.state.inSegment) then return end

  local now = GetTime()
  local last = P.lastPressAt or 0
  if last > 0 and (now - last) < 0.005 then
    return
  end

  P.lastPressAt = now
  if type(NS.OnPress) == "function" then
    NS:OnPress(now)
  end
end

local function HookGlobal(name)
  if type(_G[name]) == "function" then
    hooksecurefunc(name, RecordPress)
  end
end

function P:Reset()
  self.lastPressAt = 0
end

function P:Init()
  if self.hooksInstalled then return end
  self.hooksInstalled = true
  self:Reset()

  HookGlobal("UseAction")
  HookGlobal("CastSpellByID")
  HookGlobal("CastSpellByName")
  HookGlobal("UseInventoryItem")

  if type(C_Spell) == "table" and type(C_Spell.CastSpell) == "function" then
    hooksecurefunc(C_Spell, "CastSpell", RecordPress)
  end
end
