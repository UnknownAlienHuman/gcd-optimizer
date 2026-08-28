-- GCDOptimizer_Minimap.lua
-- LibDataBroker / LibDBIcon launcher. Slash commands are owned exclusively by
-- GCDOptimizer_Core.lua.

local _, NS = ...

NS.Minimap = NS.Minimap or {}
local M = NS.Minimap

local function EnsureDB()
  local cfg = NS:GetConfig()
  if type(cfg.minimap) ~= "table" then cfg.minimap = { hide = false } end
  if cfg.minimap.hide == nil then cfg.minimap.hide = false end
  return cfg.minimap
end

local function ToggleHUD()
  local cfg = NS:GetConfig()
  NS:SetHUDShown(not cfg.showHUD)
end

local function ToggleSegment()
  local now = GetTime()
  if NS.state and NS.state.inSegment then
    NS.state.autoCombat = false
    NS:PauseSegment(now)
  else
    NS.state.autoCombat = false
    NS:StartSegment(now)
  end
  if NS.HUD and NS.HUD.Update then NS.HUD:Update(true) end
end

local function ResetSegment()
  NS:ResetAndContinue(GetTime())
  if NS.HUD and NS.HUD.Update then NS.HUD:Update(true) end
end

function M:SetIconShown(shown)
  local db = EnsureDB()
  db.hide = not shown
  if not self.icon then return end
  if shown then
    self.icon:Show("GCDOptimizer")
  else
    self.icon:Hide("GCDOptimizer")
  end
end

function M:Init()
  if self._inited then return end
  self._inited = true

  if not LibStub then return end
  local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
  local icon = LibStub:GetLibrary("LibDBIcon-1.0", true)
  if not (ldb and icon) then return end

  local object = ldb:NewDataObject("GCDOptimizer", {
    type = "launcher",
    text = "GCD Optimizer",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    OnClick = function(_, button)
      if button == "LeftButton" then
        ToggleHUD()
      elseif button == "RightButton" then
        if IsShiftKeyDown() then ResetSegment() else ToggleSegment() end
      end
    end,
    OnTooltipShow = function(tooltip)
      local running = NS.state and NS.state.inSegment
      local paused = NS.state and NS.state.manualPaused
      local status = running and "RUNNING" or (paused and "PAUSED" or "IDLE")
      tooltip:AddLine("GCD Optimizer", 1, 1, 1)
      tooltip:AddLine("Status: " .. status, 0.9, 0.9, 0.9)
      tooltip:AddLine(" ")
      tooltip:AddLine("Left Click: Toggle window", 0.9, 0.9, 0.9)
      tooltip:AddLine("Right Click: Start/Stop tracking", 0.9, 0.9, 0.9)
      tooltip:AddLine("Shift+Right Click: Reset", 0.9, 0.9, 0.9)
    end,
  })

  self.object = object
  self.icon = icon
  icon:Register("GCDOptimizer", object, EnsureDB())
  self:SetIconShown(not EnsureDB().hide)
  NS.minimapLDB = object
end
