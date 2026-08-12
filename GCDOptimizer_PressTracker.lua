-- GCDOptimizer_PressTracker.lua
-- Captures player "press attempts" via secure hooks (local client-side).
-- We record timestamps only (optionally kind/id for future debug).
-- Dedupe: ignore presses within 5ms to avoid double hooks (UseAction + CastSpell* chains).

local _, NS = ...
NS.PressTracker = NS.PressTracker or {}
local P = NS.PressTracker

local function Now()
  return GetTime()
end

function P:Reset()
  self.lastPressAt = 0
end

local function RecordPress(kind, id)
  if not (NS.state and NS.state.inSegment) then return end
  if not (NS.Metrics and NS.Metrics.OnPress) then return end

  local now = Now()

  -- Deduplicate very tight duplicates from multiple hooks in same input chain
  if P.lastPressAt and (now - P.lastPressAt) < 0.005 then
    return
  end
  P.lastPressAt = now

  NS.Metrics:OnPress(now, kind, id)
end

function P:InstallHooks()
  if self.hooksInstalled then return end
  self.hooksInstalled = true
  self:Reset()

  -- Most action-bar keybinds go through UseAction
  hooksecurefunc("UseAction", function(slot)
    RecordPress("action", slot)
  end)

  -- Spellbook / direct casting paths (some macros)
  if CastSpellByID then
    hooksecurefunc("CastSpellByID", function(spellID)
      RecordPress("spellID", spellID)
    end)
  end

  if CastSpellByName then
    hooksecurefunc("CastSpellByName", function(spellName)
      RecordPress("spell", spellName)
    end)
  end

  -- Macro execution (very broad; may be noisy, but still reflects player input)
  if RunMacroText then
    hooksecurefunc("RunMacroText", function()
      RecordPress("macro", 0)
    end)
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  P:InstallHooks()
end)
