local ROOT = "./"

local failures = 0
local function check(condition, message)
  if not condition then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end

_G = _G or _ENV
GCDOptimizerDB = {
  __schemaVersion = 1,
  localeOverride = "ruRU",
  analysisUpdateInterval = 7,
  recommendMultiBadThr = 0.25,
}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { messages = {} }
function DEFAULT_CHAT_FRAME:AddMessage(message) self.messages[#self.messages + 1] = message end

local now = 1
function GetTime() return now end
function GetLocale() return "enUS" end
function GetCVar(name) return name == "SpellQueueWindow" and "400" or "0" end
local setCVarCalls = 0
function SetCVar() setCVarCalls = setCVarCalls + 1 end
function GetNetStats() return 0, 0, 20, 30 end
function GetCursorPosition() return 100, 100 end
function UnitAffectingCombat() return false end
local inCombatLockdown = false
function InCombatLockdown() return inCombatLockdown end
function UnitAttackSpeed() return 2.0, nil end
function canaccessallvalues() return true end
function canaccesstable(value) return type(value) == "table" end

C_Spell = {
  GetSpellCooldown = function()
    return { isActive = false, startTime = 0, duration = 0, modRate = 1 }
  end,
}

local function Noop() end
local function NewFontString()
  return setmetatable({ text = "" }, {
    __index = function(_, key)
      if key == "SetText" then return function(self, text) self.text = text end end
      if key == "GetStringWidth" then return function(self) return #(self.text or "") * 6 end end
      return Noop
    end,
  })
end

local function NewFrame()
  local frame = { shown = true, scripts = {}, width = 100, height = 100 }
  local methods = {}
  function methods:SetSize(width, height) self.width, self.height = width, height end
  function methods:SetWidth(width) self.width = width end
  function methods:SetHeight(height) self.height = height end
  function methods:GetWidth() return self.width end
  function methods:GetHeight() return self.height end
  function methods:SetScript(kind, callback) self.scripts[kind] = callback end
  function methods:GetScript(kind) return self.scripts[kind] end
  function methods:HookScript(kind, callback) self.scripts["hook_" .. kind] = callback end
  function methods:SetShown(shown) self.shown = shown and true or false end
  function methods:IsShown() return self.shown end
  function methods:IsVisible() return self.shown end
  function methods:Show() self.shown = true end
  function methods:Hide() self.shown = false end
  function methods:CreateFontString() return NewFontString() end
  function methods:GetEffectiveScale() return 1 end
  function methods:GetText() return self.text or "" end
  function methods:SetText(text) self.text = text end
  function methods:SetEnabled(enabled) self.enabled = enabled end
  function methods:Cancel() self.cancelled = true end
  setmetatable(frame, {
    __index = function(_, key) return methods[key] or Noop end,
  })
  return frame
end

UIParent = NewFrame()
function CreateFrame() return NewFrame() end

C_Timer = {}
function C_Timer.NewTicker(_, callback)
  local ticker = NewFrame()
  ticker.callback = callback
  return ticker
end
function C_Timer.NewTimer(_, callback)
  local timer = NewFrame()
  timer.callback = callback
  return timer
end

local NS = {}
function NS:L(_, fallback) return fallback end
function NS:LT(tag) return tag end

assert(loadfile(ROOT .. "GCDOptimizer_Util.lua"))("GCDOptimizer", NS)
assert(loadfile(ROOT .. "GCDOptimizer_GCDEstimator.lua"))("GCDOptimizer", NS)
assert(loadfile(ROOT .. "GCDOptimizer_Integrator.lua"))("GCDOptimizer", NS)
assert(loadfile(ROOT .. "GCDOptimizer_Metrics.lua"))("GCDOptimizer", NS)
assert(loadfile(ROOT .. "GCDOptimizer_GCDDetector.lua"))("GCDOptimizer", NS)

NS.PressTracker = { Init = Noop, Reset = Noop }
NS.Anchors = {
  Init = Noop, Reset = Noop, OnSegmentStart = Noop, OnSegmentEnd = Noop,
  GetRecentEvents = function() return {} end,
}
NS.Failures = {
  Init = Noop, Reset = Noop, OnSegmentStart = Noop, OnSegmentEnd = Noop,
  GetSegmentSummary = function() return { total = 0, topCat = "OTH", topShare = 0 } end,
}
NS.Options = { Init = Noop }
NS.Minimap = { Init = Noop, SetIconShown = Noop }

assert(loadfile(ROOT .. "GCDOptimizer_HUD.lua"))("GCDOptimizer", NS)
assert(loadfile(ROOT .. "GCDOptimizer_Core.lua"))("GCDOptimizer", NS)

NS:Init()
check(NS._inited == true, "core initialized")
check(NS.HUD.frame ~= nil and NS.HUD.frame:IsShown(), "HUD initialized and visible")
check(GCDOptimizerDB.__schemaVersion == 2, "database schema migrated")
check(GCDOptimizerDB.__addonVersion == NS.VERSION, "database version stamped")
check(GCDOptimizerDB.localeOverride == "ruRU", "compatible saved setting preserved")
check(GCDOptimizerDB.analysisUpdateInterval == nil and GCDOptimizerDB.recommendMultiBadThr == nil,
  "schema migration removes obsolete settings")
check(type(SlashCmdList.GCDOPT) == "function", "single slash dispatcher registered")

NS.HUD:ShowContextMenu()
check(NS.HUD.contextMenu and NS.HUD.contextMenu:IsShown(), "context menu created")
NS.HUD:ShowSetSQW()
check(NS.HUD.sqwPopup and NS.HUD.sqwPopup:IsShown(), "SQW popup created out of combat")
NS.HUD.sqwPopup:Hide()
inCombatLockdown = true
NS.HUD:ShowSetSQW()
check(not NS.HUD.sqwPopup:IsShown(), "SQW popup stays closed in combat lockdown")
check(setCVarCalls == 0, "combat guard prevents CVar writes")
inCombatLockdown = false

NS.state.autoCombat = false
check(NS:StartSegment(now), "manual segment starts")
check(NS.state.inSegment == true, "segment state active")
check(NS.GCDDetector.ticker ~= nil, "detector ticker active")
check(NS.HUD.ticker ~= nil, "HUD ticker active")
local manualStart = NS.state.segmentStart
NS:OnCombatStart()
check(NS.state.inSegment and not NS.state.autoCombat and NS.state.segmentStart == manualStart,
  "combat automation preserves an explicit manual segment")
check(NS:PauseSegment(now + 2), "segment stops")
check(NS.GCDDetector.ticker == nil, "detector ticker cancelled")
check(NS.HUD.ticker == nil, "HUD ticker cancelled")

SlashCmdList.GCDOPT("debug")
check(#DEFAULT_CHAT_FRAME.messages > 0, "debug command prints")

if failures > 0 then error(string.format("%d test(s) failed", failures)) end
print("bootstrap tests: PASS")
