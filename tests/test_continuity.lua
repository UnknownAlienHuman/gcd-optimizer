-- Deterministic regression tests; plain Lua, no WoW client or production hooks.
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
  _G.GCDOptimizerDB = nil
  _G.SlashCmdList = {}
  _G.GetTime = function() return w.now end
  _G.GetCVar = function() return "400" end
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
  _G.CreateFrame = function()
    local f = { scripts = {} }
    function f:RegisterEvent() end
    function f:RegisterUnitEvent() end
    function f:SetScript(name, callback) self.scripts[name] = callback end
    return f
  end
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
  for _, module in ipairs({"Util", "GCDEstimator", "Integrator", "Metrics", "GCDDetector", "Core"}) do
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
  return w
end

for _, kind in ipairs({"unavailable", "restricted", "malformed", "policy"}) do
  test("exact continuity: " .. kind, function()
    local w = world(); w:start()
    local ns, m = w.ns, w.ns.Metrics
    w.now = 100.2
    if kind == "unavailable" then w.cooldown = nil
    elseif kind == "restricted" then w:restricted()
    elseif kind == "malformed" then w.cooldown.modRate = 0 end
    ns.GCDDetector:Observe(kind == "policy" and "SPELL_SECRECY_CHANGED" or "test")
    ns:OnPress(100.9)
    w:direct(101); w:observe(101.05)
    check(m:GetObservationCounts().total == 2, "start counts survive boundary")
    check(m:GetPressClassCounts().cycles == 0, "no exact cycle may cross a blind/policy boundary")
    check(m.cycleData:Size() == 0, "no SQW evidence across boundary")
    ns:OnPress(101.9)
    w:direct(102); w:observe(102.05)
    check(m:GetPressClassCounts().cycles == 1, "exact analysis resumes after a fresh baseline")
    check(m.cycleData:Size() == 1, "next contiguous exact cycle is eligible")
  end)
end

test("same-cycle recovery keeps dedupe without reopening a blind link", function()
  local w = world(); w:start()
  w:restricted(); w:observe(100.2)
  w:direct(100); w:observe(100.3)
  check(w.ns.Metrics.actualFight == 1, "recovery does not recount the current start")
  w.ns:OnPress(100.9)
  w:direct(101); w:observe(101.05)
  check(w.ns.Metrics.cycleN == 0, "same-start refresh does not clear broken continuity")
end)

test("estimate upgrade cannot retroactively bridge a restriction", function()
  local w = world(); w:start()
  w:restricted(); w:observe(100.2)
  w.now = 101
  w.ns.GCDDetector:ScheduleEstimatedFallback(w.now)
  w.now = 101.06
  w.timers[#w.timers].callback()
  w:direct(101.02); w:observe(101.1)
  local counts = w.ns.Metrics:GetObservationCounts()
  check(counts.total == 2 and counts.direct == 2, "estimate upgraded without recounting")
  check(counts.exactCycles == 0, "upgrade preserves blind-boundary exclusion")
end)

test("stale fallback callback preserves its replacement handle", function()
  local w = world(); w.ns:StartSegment(w.now)
  local d = w.ns.GCDDetector
  d:ScheduleEstimatedFallback(100)
  local old = d.pendingFallback
  d:ScheduleEstimatedFallback(100.02)
  local replacement = d.pendingFallback
  old.callback() -- simulate a callback already queued when Cancel was issued
  check(d.pendingFallback == replacement, "obsolete callback must not clear replacement")
  d:OnSegmentEnd()
  check(replacement.cancelled, "replacement must remain reachable for teardown")
end)

test("stale poll callback cannot read in the next segment", function()
  local w = world(); w:start()
  local old = w.ns.GCDDetector.ticker
  w.ns:ResetAndContinue(100.1)
  local before = w.reads
  old.callback()
  check(w.reads == before, "old generation must not perform a new read")
end)

local function record(readHUD)
  local w = world(); w:start()
  for i = 1, 80 do
    local t = 100 + i / 20
    if t >= 101 and t < 103 then w:direct(101, 2)
    elseif t >= 103 then w:direct(103, 1) end
    w:observe(t)
    if readHUD then
      w.ns.Integrator:GetCurrentPrediction()
      w.ns.Integrator:GetPossibleFight(t)
    end
  end
  return w.ns.Integrator:GetPossibleFight(w.now)
end

test("HUD-independent integration", function()
  near(record(false), record(true), "visible and hidden HUD must produce the same integral")
  near(record(false), 3, "piecewise integral follows observed one/two-second durations")
end)

test("display getters do not query APIs or mutate integration", function()
  local w = world(); w:start()
  local i = w.ns.Integrator
  local beforeReads, beforeT, beforeTotal = w.reads, i.lastT, i.totalIntervals
  w.now = 101
  for _ = 1, 20 do i:GetCurrentPrediction(); i:GetPossibleFight(w.now) end
  check(w.reads == beforeReads, "render getters must not query cooldown API")
  check(i.lastT == beforeT and i.totalIntervals == beforeTotal, "render getters must be pure")
end)

test("end trims idle tail even after many rate changes", function()
  local w = world(); w:start()
  w.now = 100.8
  w.ns:OnPress(w.now)
  for n = 1, 700 do
    w.swing = (n % 2 == 0) and 2 or 3
    w:inactive()
    w:observe(101 + n / 10)
    w.ns.Integrator:GetCurrentPrediction()
    w.ns.Integrator:GetPossibleFight(w.now)
  end
  w.ns:PauseSegment(w.now)
  near(w.ns.Integrator:GetPossibleFight(w.now), 0.8, "idle tail must be removed from cumulative integral")
  local before = w.ns.Integrator:GetPossibleFight()
  w:direct(900, 2); w.now = 900
  w.ns.Integrator:GetCurrentPrediction()
  near(w.ns.Integrator:GetPossibleFight(), before, "stopped total remains frozen")
  local history = w.ns.Integrator.history
  check(history and history:Size() <= 256, "rate history stays bounded")
end)

test("unavailable interval is not integrated as a stale exact rate", function()
  local w = world(); w:start()
  w.cooldown = nil; w:observe(100.2)
  w:observe(109.9)
  w:direct(110); w:observe(110)
  near(w.ns.Integrator:GetPossibleFight(110), 0.2, "unknown interval contributes no invented capacity")
end)

test("new exact GCD without readable swing invalidates old calibration", function()
  local w = world(); w:start()
  w.swing = w.secret
  w:direct(101, 0.8); w:observe(101.01)
  w.swing = 2
  w:restricted()
  local duration, source = w.ns.GCDEstimator:GetFallbackPrediction()
  check(source == w.u.GCD_SOURCE_CACHED, "stale swing pair must not survive a failed new calibration")
  near(duration, 0.8, "last exact display duration remains usable")
end)

test("non-finite config cannot poison timers or recommendation loops", function()
  local w = world()
  _G.GCDOptimizerDB = { pollInterval = 0/0, recommendStepMs = 0/0,
    recommendLeadBufferMs = 0/0, anchors = { maxEvents = 0/0, fadeWindow = 0/0 } }
  local cfg = w.ns:GetConfig()
  near(cfg.pollInterval, 0.05, "NaN polling interval uses default")
  near(cfg.recommendStepMs, 5, "NaN search step uses default")
  check(cfg.recommendLeadBufferMs == nil, "invalid optional buffer is dropped")
  near(cfg.anchors.maxEvents, 300, "anchor buffer is finite")
  near(cfg.anchors.fadeWindow, 0.25, "anchor window is finite")
end)


test("ordinary inactive reads preserve exact adjacency", function()
  local w = world(); w:start()
  w:inactive(); w:observe(101.01)
  w.now = 101.1; w.ns:OnPress(w.now)
  w:direct(101.2); w:observe(101.21)
  check(w.ns.Metrics.cycleN == 1, "inactive is not a blind observation")
  check(w.ns.Metrics.attributableN == 1, "ordinary late input remains attributable")
end)

test("fallback read also establishes the restriction boundary", function()
  local w = world(); w:start()
  w:inactive(); w:observe(101.01)
  local d = w.ns.GCDDetector
  d:ScheduleEstimatedFallback(101.02)
  w:restricted(); w.now = 101.08
  w.timers[#w.timers].callback()
  w:direct(101.02); w:observe(101.1)
  check(w.ns.Metrics.actualFight == 2, "fallback can still be upgraded")
  check(w.ns.Metrics.cycleN == 0, "callback cannot bypass boundary routing")
end)

test("policy change cancels pending inference", function()
  local w = world(); w.ns:StartSegment(w.now)
  local d = w.ns.GCDDetector
  d:ScheduleEstimatedFallback(100)
  local pending = d.pendingFallback
  d:Observe("SPELL_SECRECY_CHANGED")
  check(pending.cancelled and d.pendingFallback == nil, "old-context candidate cancelled")
  local before = w.reads
  pending.callback()
  check(w.reads == before, "old-context callback cannot query")
end)

test("out-of-range duration is not accepted or integrated", function()
  local w = world(); w:start()
  w:direct(101, 30); w:observe(101)
  check(w.ns.GCDDetector.lastStatus == w.u.GCD_STATUS_MALFORMED, "invalid duration marks a boundary")
  check(w.ns.Metrics.actualFight == 1, "invalid duration creates no start")
  near(w.ns.Integrator:GetPossibleFight(103), 1, "invalid duration has zero integration rate")
end)

test("reset cancels HUD work even without immediate restart", function()
  local w = world()
  local stops = 0
  w.ns.HUD = { StopTicker = function() stops = stops + 1 end }
  w:start(); w.ns:ResetSegment(101)
  check(stops == 1, "standalone reset stops the HUD ticker")
end)

test("auto-combat first exact observation reanchors the integral", function()
  local w = world()
  w:direct(99.9, 1)
  w.ns.state.autoCombat = true
  w.ns:StartSegment(100)
  near(w.ns.state.segmentStart, 99.9, "bounded reanchor preserved")
  w:observe(100.4)
  near(w.ns.Integrator:GetPossibleFight(100.4), 0.5, "reanchor uses observed duration")
end)

test("detector ingress rejects inactive segments and cached starts", function()
  local w = world()
  local d = w.ns.GCDDetector
  d:ScheduleEstimatedFallback(100)
  check(#w.timers == 0, "stopped segment cannot schedule fallback work")
  check(not d:AcceptStart(100, 1, w.u.GCD_SOURCE_DIRECT), "stopped segment rejects starts")
  w:start()
  local before = w.ns.Metrics.actualFight
  check(not d:AcceptStart(102, 1, w.u.GCD_SOURCE_CACHED), "cached duration never creates a start")
  check(w.ns.Metrics.actualFight == before, "rejected source preserves counts")
end)

print(string.format("continuity tests: %d cases, %d assertions, %d failed", cases, assertions, failed))
if failed > 0 then os.exit(1) end
