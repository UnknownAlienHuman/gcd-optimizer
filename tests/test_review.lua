-- Full-module regression scenarios for analytics freshness and UI lifecycle.
-- The UI mock implements only named APIs; unknown members stay nil.
local cases, assertions, failed = 0, 0, 0
local function check(value, message)
  assertions = assertions + 1
  assert(value, message)
end
local function near(value, expected, message)
  check(type(value) == "number" and math.abs(value - expected) < 1e-7,
    message .. ": got " .. tostring(value) .. ", expected " .. tostring(expected))
end
local function test(name, run)
  cases = cases + 1
  local ok, err = pcall(run)
  if not ok then failed = failed + 1; io.stderr:write("FAIL " .. name .. ": " .. tostring(err) .. "\n") end
end

local function world()
  local w = { now = 100, reads = 0, timers = {}, tickers = {}, swing = 2 }
  local secret = {}
  w.secret = secret
  _G.GCDOptimizerDB = { showHUD = false }
  _G.SlashCmdList = {}
  _G.GetTime = function() return w.now end
  w.queueWindow = 400
  w.combat = false
  _G.GetCVar = function() return tostring(w.queueWindow) end
  _G.InCombatLockdown = function() return w.combat end
  _G.UnitAffectingCombat = function() return w.combat end
  _G.GetCursorPosition = function() return 0, 0 end
  _G.SetCVar = function(_, value) w.queueWindow = tonumber(value) end
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  _G.GetNetStats = function() return 0, 0, 20, 40 end
  _G.UnitAttackSpeed = function() return w.swing end
  _G.canaccessallvalues = function(...)
    for i = 1, select("#", ...) do
      if select(i, ...) == secret then return false end
    end
    return true
  end
  _G.canaccesstable = function(t) return type(t) == "table" end
  _G.geterrorhandler = function() return function(err) error(err, 0) end end
  local methods = {}
  local function noop() end
  for _, name in ipairs({
    "RegisterEvent", "RegisterUnitEvent", "SetPoint", "ClearAllPoints",
    "SetFrameStrata", "SetClampedToScreen", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetMovable", "EnableMouse", "RegisterForDrag",
    "StartMoving", "StopMovingOrSizing", "SetJustifyH", "SetNumeric",
    "SetAutoFocus", "SetFocus", "HighlightText", "SetEnabled", "SetScrollChild",
  }) do methods[name] = noop end
  function methods:SetSize(wi, he) self.width, self.height = wi, he end
  function methods:SetWidth(wi) self.width = wi end
  function methods:SetHeight(he) self.height = he end
  function methods:GetWidth() return self.width end
  function methods:GetHeight() return self.height end
  function methods:GetEffectiveScale() return 1 end
  function methods:SetScript(name, callback) self.scripts[name] = callback end
  function methods:GetScript(name) return self.scripts[name] end
  function methods:IsShown() return self.shown end
  function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
  function methods:SetShown(shown)
    shown = not not shown
    if shown == self.shown then return end
    self.shown = shown
    local callback = self.scripts[shown and "OnShow" or "OnHide"]
    if callback then callback(self) end
  end
  function methods:Show() self:SetShown(true) end
  function methods:Hide() self:SetShown(false) end
  function methods:SetText(text) self.text = text end
  function methods:GetText() return self.text or "" end
  function methods:GetStringWidth() return #(self.text or "") * 6 end
  local function widget(parent)
    return setmetatable({ parent = parent, shown = true, scripts = {}, width = 100, height = 100 }, { __index = methods })
  end
  function methods:CreateFontString() return widget(self) end
  _G.UIParent = widget()
  _G.CreateFrame = function(_, _, parent) return widget(parent) end
  local function timer(list, callback)
    local t = { callback = callback, cancelled = false }
    function t:Cancel() self.cancelled = true end
    list[#list + 1] = t
    return t
  end
  _G.C_Timer = {
    NewTicker = function(_, callback) return timer(w.tickers, callback) end,
    NewTimer = function(_, callback) return timer(w.timers, callback) end,
  }
  _G.C_Spell = { GetSpellCooldown = function() w.reads = w.reads + 1; return w.cooldown end }
  w.cooldown = { isActive = false, startTime = 0, duration = 0, modRate = 1 }
  local ns = {}
  function ns:L(_, fallback) return fallback end
  function ns:LT(tag) return tag end
  for _, module in ipairs({"Util", "GCDEstimator", "Integrator", "Metrics", "GCDDetector", "HUD", "Core"}) do
    assert(loadfile("GCDOptimizer_" .. module .. ".lua"))("GCDOptimizer", ns)
  end
  ns:Init()
  w.ns = ns
  w.u = ns.Util
  function w:direct(startTime, duration)
    self.cooldown = { isActive = true, startTime = startTime, duration = duration or 1, modRate = 1 }
  end
  function w:restricted()
    self.cooldown = { isActive = true, startTime = secret, duration = secret, modRate = secret }
  end
  function w:inactive()
    self.cooldown = { isActive = false, startTime = 0, duration = 0, modRate = 1 }
  end
  function w:observe(timestamp)
    self.now = timestamp
    self.ns.GCDDetector:Observe("test")
  end
  function w:start()
    self:direct(self.now)
    self.ns:StartSegment(self.now)
  end
  function w:cycle(pressCount, gap)
    local ready = self.ns.Metrics.lastReadyTime
    local start = ready + (gap or 0)
    for n = 1, pressCount do
      self.now = start - 0.15 + (n - 1) * 0.05
      self.ns:OnPress(self.now)
    end
    self:direct(start)
    self:observe(start)
  end
  return w
end

test("old single-press samples expire through ambiguous cycles", function()
  local w = world(); w:start()
  for _ = 1, 20 do w:cycle(1) end
  local _, before = w.ns.Metrics:RecommendSpellQueueWindow()
  check(not before.lowSample, "baseline has enough eligible cycles")
  for _ = 1, 60 do w:cycle(2) end
  local _, after = w.ns.Metrics:RecommendSpellQueueWindow()
  check(after.lowSample and after.sampleN == 0, "new ambiguous cycles must retire old recommendations")
end)

test("old single-press samples expire through unobserved cycles", function()
  local w = world(); w:start()
  for _ = 1, 20 do w:cycle(1) end
  for _ = 1, 60 do w:cycle(0) end
  local _, info = w.ns.Metrics:RecommendSpellQueueWindow()
  check(info.lowSample and info.sampleN == 0, "no hook evidence must not preserve a stale recommendation")
end)

test("recommendation lead buffer uses its current evidence epoch", function()
  local w = world(); w:start()
  for _ = 1, 20 do w:cycle(1) end
  w.ns.Metrics:BreakContinuity()
  w:cycle(0) -- new exact baseline
  for _ = 1, 20 do w:cycle(1, 0.3) end -- single late presses, no queued lead
  local value, info = w.ns.Metrics:RecommendSpellQueueWindow()
  check(value == nil and info.noQueueEvidence, "late-only evidence cannot justify changing SQW")
  near(info.medianLeadMs, 0, "old queue lead must not affect a new evidence epoch")
end)

test("SQW search includes the configured maximum", function()
  local w = world(); w:start()
  local cfg = w.ns:GetConfig()
  cfg.recommendStepMs = 30
  for _ = 1, 20 do
    local ready = w.ns.Metrics.lastReadyTime
    w.ns:OnPress(ready - 0.395)
    w:direct(ready); w:observe(ready)
  end
  local value, info = w.ns.Metrics:RecommendSpellQueueWindow()
  near(value, 400, "maximum is eligible even when the grid ends at 380")
  near(info.coverage, 1, "diagnostics describe the returned window")
end)

test("rolling context returns local sample counts", function()
  local w = world(); w:start()
  for _ = 1, 20 do w:cycle(2) end
  for _ = 1, 10 do w:cycle(1) end
  local c = w.ns.Metrics:ComputeContext(5, w.now)
  check(c.cycles == 6 and c.attributable == 6, "five-second inclusive window has six current cycles")
  check(c.ambiguous == 0 and c.unobserved == 0, "old ambiguity cannot stick to the new window")
end)

test("full context does not lose totals after cycle-log eviction", function()
  local w = world(); w:start()
  for _ = 1, 700 do w:cycle(1, 0.6) end
  local m = w.ns.Metrics
  local c = m:ComputeContext(nil, w.now)
  check(m.cycleLog:Size() == 600, "rolling log stays bounded")
  check(c.cycles == 700 and c.attributable == 700, "segment totals cover all cycles")
  near(c.afkTime, 700 * 0.18, "full gap total survives ring eviction")
end)

test("one old hook does not prove inactivity during continued GCDs", function()
  local w = world(); w:start(); w.combat = true
  w.ns:OnPress(w.now)
  for _ = 1, 15 do w:cycle(0) end
  w.ns:SetHUDShown(true)
  local s = w.ns.HUD.lastSnapshot
  check(not s.analysisText:find("Stop sleeping", 1, true), "continued cadence must not be called sleeping")
  check(s.verdictTag == "Low sample", "unobserved input cannot support a skill verdict")
end)

test("old ambiguity does not poison a clean current window", function()
  local w = world(); w:start(); w.combat = true
  for _ = 1, 30 do w:cycle(2) end
  for _ = 1, 10 do w:cycle(1) end
  w.ns:SetHUDShown(true)
  check(w.ns.HUD.lastSnapshot.verdictTag == "OK", "rolling verdict uses rolling ambiguity")
end)

test("old counts do not make one late sample statistically sufficient", function()
  local w = world(); w:start(); w.combat = true
  for _ = 1, 30 do w:cycle(1) end
  w:inactive(); w:observe(w.now + 8)
  local start = w.now + 0.2
  w.ns:OnPress(start - 0.1)
  w:direct(start); w:observe(start)
  w.ns:SetHUDShown(true)
  check(w.ns.HUD.lastSnapshot.verdictTag == "Low sample", "lifetime sample count cannot validate a sparse live window")
end)

test("paused report does not change with later combat or wall time", function()
  local w = world(); w:start()
  for _ = 1, 25 do w:cycle(1) end
  w.ns:PauseSegment(w.now)
  w.ns:SetHUDShown(true)
  local before = w.ns.HUD.lastSnapshot.analysisText
  w.combat = true; w.now = w.now + 100
  w.ns.HUD:Update(true)
  check(w.ns.HUD.lastSnapshot.analysisText == before, "final verdict remains frozen")
end)

test("hidden HUD closes all transient windows", function()
  local w = world(); w.ns:SetHUDShown(true)
  local h = w.ns.HUD
  h:SetDetailsShown(true); h:ShowContextMenu(); h:ShowSetSQW()
  w.ns:SetHUDShown(false)
  check(not h.detailsFrame:IsShown() and not h.contextMenu:IsShown() and not h.sqwPopup:IsShown(),
    "details, menu and CVar editor share HUD visibility ownership")
  check(h.expandButton:GetText() == ">", "expand icon follows closed details")
end)

test("direct frame hide cancels HUD work", function()
  local w = world(); w:start(); w.ns:SetHUDShown(true)
  local h, ticker = w.ns.HUD, w.ns.HUD.ticker
  h.frame:Hide()
  check(ticker.cancelled and h.ticker == nil, "OnHide tears down its ticker")
end)

test("stale HUD callbacks cannot update a replacement segment", function()
  local w = world(); w:start(); w.ns:SetHUDShown(true)
  local h, old = w.ns.HUD, w.ns.HUD.ticker
  w.ns:ResetAndContinue(w.now + 1)
  local calls = 0
  h.Update = function() calls = calls + 1 end
  old.callback()
  check(calls == 0, "cancelled HUD generation cannot render a new segment")
end)

test("stale menu Start cannot steal an automatic segment", function()
  local w = world(); w.ns:SetHUDShown(true)
  local h = w.ns.HUD
  h:ShowContextMenu()
  local click = h.contextMenu.buttons[1]:GetScript("OnClick")
  w.ns:OnCombatStart()
  check(w.ns.state.autoCombat, "automatic segment started")
  click()
  check(w.ns.state.autoCombat, "stale Start keeps the existing automatic owner")
  w.ns:OnCombatEnd()
  check(not w.ns.state.inSegment, "automatic end policy remains intact")
end)

test("same-start duration correction invalidates its old swing pair", function()
  local w = world(); w:start()
  w:direct(100, 0.8); w:observe(100.1)
  w:restricted(); w:observe(100.2)
  local duration, source = w.ns.GCDEstimator:GetFallbackPrediction()
  near(duration, 0.8, "display retains the corrected exact duration")
  check(source == w.u.GCD_SOURCE_CACHED, "do not reuse an inconsistent swing calibration")
end)

test("HUD does not consume restriction-sensitive unit combat state", function()
  local w = world(); w:start(); w.combat = true
  UnitAffectingCombat = function() error("unit combat read must not be used") end
  w.ns:SetHUDShown(true)
  check(w.ns.HUD.lastSnapshot ~= nil, "public lockdown state is sufficient for display mode")
end)


test("sub-threshold duration steps accumulate against the last forwarded value", function()
  local w = world(); w:start()
  for n = 1, 3 do
    w:direct(100, 1 - n * 0.0004); w:observe(100 + n * 0.05)
  end
  near(w.ns.Metrics.lastGCDDur, 0.9988, "small changes must not leave metrics permanently stale")
  check(w.ns.GCDDetector.exactCount == 1, "duration correction does not add another start")
end)

test("cumulative same-start drift invalidates the original calibrated pair", function()
  local w = world(); w:start()
  for n = 1, 3 do
    w:direct(100, 1 - n * 0.0004); w:observe(100 + n * 0.05)
  end
  w:restricted(); w:observe(100.2)
  local duration, source = w.ns.GCDEstimator:GetFallbackPrediction()
  near(duration, 0.9988, "display retains the latest duration")
  check(source == w.u.GCD_SOURCE_CACHED, "compare corrections to the calibrated pair, not just the previous poll")
end)

test("optimized SQW search agrees with an independent exhaustive reference", function()
  local w = world(); w:start()
  local m, cfg = w.ns.Metrics, w.ns:GetConfig()
  local seed = 12345
  local function random(n)
    seed = (seed * 16807) % 2147483647
    return seed % n
  end
  for trial = 1, 120 do
    local maximum, step = 50 + random(951), 1 + random(50)
    local latency, buffer = random(700), random(150)
    local sampleCount = 20 + random(41)
    cfg.recommendMaxMs, cfg.recommendStepMs = maximum, step
    cfg.recommendLeadBufferMs = buffer
    GetNetStats = function() return 0, 0, latency, latency end
    m.cycleData = w.u.Deque:New()
    local leads = {}
    for n = 1, sampleCount do
      local lead = random(maximum + 250) - 100
      if n == 1 then lead = 0 end -- at least one queue sample
      leads[n] = lead
      m.cycleData:PushBack({ ready = 100, start = 102, press = 100 - lead / 1000, observation = n })
    end
    local function covered(window)
      local count = 0
      for _, lead in ipairs(leads) do
        if lead >= 0 and lead <= window + 1e-6 then count = count + 1 end
      end
      return count / sampleCount
    end
    local minimum = math.min(maximum, math.floor(math.max(50, latency * cfg.recommendLatencyFactor)))
    local best, score = minimum, -math.huge
    local candidate = minimum
    while true do
      local current = covered(candidate) - candidate / 10000
      if current > score then best, score = candidate, current end
      if candidate == maximum then break end
      candidate = math.min(candidate + step, maximum)
    end
    local expected = math.min(maximum, math.max(best, math.floor(latency + buffer)))
    local actual, info = m:RecommendSpellQueueWindow()
    near(actual, expected, "reference window " .. trial)
    near(info.coverage, covered(expected), "coverage of returned window " .. trial)
  end
end)

test("queue and late shares exclude unattributable inputs from their denominator", function()
  local w = world(); w:start()
  w:cycle(1); w:cycle(1); w:cycle(1, 0.3)
  w:cycle(0); w:cycle(2)
  local c = w.ns.Metrics:ComputeContext(nil, w.now)
  check(c.cycles == 5 and c.attributable == 3, "total and attributable populations are distinct")
  near(c.qHit, 2 / 3, "queued share among attributed input")
  near(c.lateShare, 1 / 3, "late share among attributed input")
  near(c.qCov, 3 / 5, "coverage includes ambiguous queue input")
end)

test("combat entered after opening SQW blocks the apply callback", function()
  local w = world(); local h = w.ns.HUD
  h:ShowSetSQW()
  h.sqwPopup.edit:SetText("250")
  local apply = h.sqwPopup.edit:GetScript("OnEnterPressed")
  w.combat = true
  apply()
  near(w.queueWindow, 400, "late combat transition does not write the CVar")
  w.combat = false
  apply()
  near(w.queueWindow, 250, "same editor works after combat")
  h:ShowSetSQW(); h.sqwPopup.edit:SetText("180")
  h.sqwPopup.edit:GetScript("OnEnterPressed")()
  near(w.queueWindow, 180, "reopening preserves the apply callback")
end)

test("live verdict can collect enough evidence for a 1.5-second GCD", function()
  local w = world(); w.combat = true
  w:direct(100, 1.5); w.ns:StartSegment(100)
  for _ = 1, 20 do
    local ready = w.ns.Metrics.lastReadyTime
    w.ns:OnPress(ready - 0.15)
    w:direct(ready, 1.5); w:observe(ready)
  end
  w.ns:SetHUDShown(true)
  check(w.ns.HUD.lastSnapshot.verdictTag == "OK", "normal 1.5-second cadence must not be permanently low-sample")
end)

test("live verdict requires fresh samples after a blind boundary", function()
  local w = world(); w:start(); w.combat = true
  for _ = 1, 25 do w:cycle(1) end
  w:restricted(); w:observe(w.now + 0.1)
  w:cycle(1) -- recovery baseline, not an analyzable exact cycle
  w.ns:SetHUDShown(true)
  check(w.ns.HUD.lastSnapshot.verdictTag == "Low sample", "pre-boundary cycles cannot validate recovery")
end)

print(string.format("review tests: %d cases, %d assertions, %d failed", cases, assertions, failed))
if failed > 0 then os.exit(1) end
