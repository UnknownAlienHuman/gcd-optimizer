-- GCDOptimizer_Minimap.lua
-- Minimap launcher using LibDataBroker + LibDBIcon-1.0 (required by button organizers)

local _, NS = ...
GCDOptimizerDB = GCDOptimizerDB or {}

local function EnsureDB()
  GCDOptimizerDB.minimap = GCDOptimizerDB.minimap or { hide = false }
  return GCDOptimizerDB.minimap
end

local function EnsureHUD()
  if NS.HUD and NS.HUD.frame then return end
  if NS.HUD and NS.HUD.Init then NS.HUD:Init() end
end

local function ToggleHUD()
  EnsureHUD()
  local cfg = NS:GetConfig()
  cfg.showHUD = not cfg.showHUD
  local f = NS.HUD and NS.HUD.frame
  if not f then return end
  f:SetShown(cfg.showHUD)
  if cfg.showHUD then
    if NS.HUD.StartTicker then NS.HUD:StartTicker() end
    if NS.HUD.Update then NS.HUD:Update(true) end
  else
    if NS.HUD.StopTicker then NS.HUD:StopTicker() end
    if NS.HUD.detailsFrame then NS.HUD.detailsFrame:Hide() end
  end
end

local function ToggleSegment()
  local now = GetTime()
  if NS.state and NS.state.inSegment then
    NS:PauseSegment(now)
  else
    NS:StartSegment(now)
  end
  if NS.HUD and NS.HUD.Update then NS.HUD:Update() end
end

local function ResetSegment()
  NS:ResetSegment(GetTime())
  if NS.HUD and NS.HUD.Update then NS.HUD:Update() end
end

local function TooltipLines()
  local inSeg = NS.state and NS.state.inSegment
  local paused = NS.state and NS.state.manualPaused
  local status = inSeg and "RUNNING" or (paused and "PAUSED" or "IDLE")
  return {
    "GCD Optimizer",
    "Status: " .. status,
    " ",
    "Left Click: Toggle window",
    "Right Click: Start/Stop tracking",
    "Shift+Right Click: Reset",
  }
end

local function InitLDB()
  if not LibStub then return end
  local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
  if not ldb then return end

  local obj = ldb:NewDataObject("GCDOptimizer", {
    type = "launcher",
    text = "GCDOptimizer",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    OnClick = function(_, button)
      if button == "LeftButton" then
        ToggleHUD()
      elseif button == "RightButton" then
        if IsShiftKeyDown() then
          ResetSegment()
        else
          ToggleSegment()
        end
      end
    end,
    OnTooltipShow = function(tt)
      local lines = TooltipLines()
      tt:AddLine(lines[1], 1, 1, 1)
      for i = 2, #lines do
        tt:AddLine(lines[i], 0.9, 0.9, 0.9, true)
      end
    end,
  })

  local icon = LibStub:GetLibrary("LibDBIcon-1.0", true)
  if not icon then return end

  icon:Register("GCDOptimizer", obj, EnsureDB())
  if EnsureDB().hide then
    icon:Hide("GCDOptimizer")
  else
    icon:Show("GCDOptimizer")
  end

  NS.minimapLDB = obj
end

-- Slash helpers
SLASH_GCDOPT1 = "/gcdopt"
SlashCmdList["GCDOPT"] = function(msg)
  msg = (msg or ""):lower()

  if msg == "reset" then
    ResetSegment()
    return
  end
  if msg == "start" then
    if not (NS.state and NS.state.inSegment) then NS:StartSegment(GetTime()) end
    return
  end
  if msg == "stop" then
    if NS.state and NS.state.inSegment then NS:PauseSegment(GetTime()) end
    return
  end
  if msg == "hide" then
    local icon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    EnsureDB().hide = true
    if icon then icon:Hide("GCDOptimizer") end
    return
  end
  if msg == "show" then
    local icon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    EnsureDB().hide = false
    if icon then icon:Show("GCDOptimizer") end
    return
  end

  ToggleHUD()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  EnsureDB()
  InitLDB()
end)
