-- Regressions for bounded input history, idle calibration and saved settings.
local cases, assertions, failures = 0, 0, 0
local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end
local function near(actual, expected, message)
  check(type(actual) == "number" and math.abs(actual - expected) < 1e-7, message)
end
local function test(name, callback)
  cases = cases + 1
  local ok, err = pcall(callback)
  if not ok then
    failures = failures + 1
    io.stderr:write("FAIL " .. name .. ": " .. tostring(err) .. "\n")
  end
end
local function world(database)
  local w = { now = 100, combat = false, swing = 2, frames = {}, timers = {}, tickers = {}, reads = 0 }
  local secret = {}
  w.secret = secret
  GCDOptimizerDB, SlashCmdList = database, {}
  GetTime = function() return w.now end
  GetCVar = function() return "400" end
  GetNetStats = function() return 0, 0, 20, 40 end
  InCombatLockdown = function() return w.combat end
  UnitAttackSpeed = function() return w.swing end
  canaccessallvalues = function(...)
    for i = 1, select("#", ...) do
      if select(i, ...) == secret then return false end
    end
    return true
  end
  canaccesstable = function(t) return type(t) == "table" and t ~= secret end
  geterrorhandler = function() return function(err) error(err, 0) end end
  CreateFrame = function()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:RegisterUnitEvent(event) self.events[event] = true end
    function f:SetScript(kind, callback) self.scripts[kind] = callback end
    w.frames[#w.frames + 1] = f
    return f
  end
  local function timer(list, callback)
    local t = { callback = callback }
    function t:Cancel() self.cancelled = true end
    list[#list + 1] = t
    return t
  end
  C_Timer = {
    NewTimer = function(_, callback) return timer(w.timers, callback) end,
    NewTicker = function(_, callback) return timer(w.tickers, callback) end,
  }
  w.cooldown = { isActive = false, startTime = 0, duration = 0, modRate = 1 }
  C_Spell = { GetSpellCooldown = function() w.reads = w.reads + 1; return w.cooldown end }
  local ns = {}
  for _, module in ipairs({ "Util", "GCDEstimator", "Integrator", "Metrics", "GCDDetector", "Core" }) do
    assert(loadfile("GCDOptimizer_" .. module .. ".lua"))("GCDOptimizer", ns)
  end
  ns:Init()
  w.ns, w.m, w.u = ns, ns.Metrics, ns.Util
  function w:fire(event)
    for _, f in ipairs(self.frames) do
      if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end
    end
  end
  function w:direct(start, duration)
    self.cooldown = { isActive = true, startTime = start, duration = duration or 1, modRate = 1 }
  end
  function w:restricted()
    self.cooldown = { isActive = true, startTime = secret, duration = secret, modRate = secret }
  end
  function w:baseline()
    self.m:OnSegmentStart(100)
    self.m:OnGCDStart(100, 1, self.u.GCD_SOURCE_DIRECT)
  end
  return w
end

test("time eviction cannot turn ambiguous input into a single late press", function()
  local w = world(); w:baseline()
  w.m:OnPress(100.8); w.m:OnPress(109)
  w.m:OnGCDStart(109.1, 1, w.u.GCD_SOURCE_DIRECT)
  check(w.m.attributableN == 0, "evicted candidate must not make the remaining press exact")
  check(w.m.cycleData:Size() == 0, "incomplete history must not feed SQW")
  check(w.m:GetObservationCounts().incomplete == 1, "incomplete input is reported separately")
  check(w.m.actualFight == 2 and w.m.cycleN == 1, "ordinary cadence counts are retained")
end)

test("capacity eviction before a delayed read cannot create exact attribution", function()
  local w = world({ pressBufferMax = 100 }); w:baseline()
  w.m:OnPress(100.7); w.m:OnPress(100.9)
  for i = 1, 99 do w.m:OnPress(101 + i * 0.006) end
  w.m:OnGCDStart(101, 1, w.u.GCD_SOURCE_DIRECT)
  check(w.m.pressQueue:Size() == 100, "input storage remains bounded")
  check(w.m.attributableN == 0 and w.m.cycleData:Size() == 0, "lost history is not exact evidence")
end)

test("eviction before the attribution window does not discard valid evidence", function()
  local w = world({ pressBufferMax = 100 }); w:baseline()
  for i = 1, 100 do w.m:OnPress(100 + i * 0.005) end
  w.m:OnPress(100.9)
  w.m:OnGCDStart(101, 1, w.u.GCD_SOURCE_DIRECT)
  check(w.m.attributableN == 1 and w.m.queuedN == 1, "unrelated old evictions do not disable attribution")
end)

test("discarded timestamp at the inclusive window edge is incomplete", function()
  local w = world({ pressBufferMax = 100 }); w:baseline()
  w.m:OnPress(100.6); w.m:OnPress(100.9)
  for i = 1, 99 do w.m:OnPress(101 + i * 0.006) end
  w.m:OnGCDStart(101, 1, w.u.GCD_SOURCE_DIRECT)
  check(w.m.attributableN == 0, "the inclusive lower edge is covered by the eviction watermark")
end)

test("fresh input recovers without resetting segment totals", function()
  local w = world(); w:baseline()
  w.m:OnPress(100.8); w.m:OnPress(109)
  w.m:OnGCDStart(109.1, 1, w.u.GCD_SOURCE_DIRECT)
  w.m:OnPress(110)
  w.m:OnGCDStart(110.1, 1, w.u.GCD_SOURCE_DIRECT)
  check(w.m:GetObservationCounts().incomplete == 1, "incomplete count survives recovery")
  check(w.m.attributableN == 1 and w.m.cycleData:Size() == 1, "fresh complete interval resumes SQW")
end)

test("incomplete input stays distinct in rolling and segment summaries", function()
  local w = world(); w:baseline()
  w.m:OnPress(100.8); w.m:OnPress(109)
  w.m:OnGCDStart(109.1, 1, w.u.GCD_SOURCE_DIRECT)
  for _, window in ipairs({ 0, 10 }) do
    local c = w.m:ComputeContext(window, 109.1)
    check(c.incomplete == 1 and c.attributable == 0, "summary must preserve incomplete classification")
    check(c.cycles == c.attributable + c.ambiguous + c.unobserved + c.incomplete, "classes partition exact cycles")
    check(c.afkDen == 0, "missing press history cannot establish absence of presses during a gap")
  end
end)

test("boundary clearing records post-start inputs that were discarded", function()
  local w = world(); w:baseline()
  GetCVar = function() return "4000" end
  w.m:BreakContinuity()
  w.m:OnPress(101.2)
  w.m:OnGCDStart(101, 1, w.u.GCD_SOURCE_DIRECT)
  w.m:OnPress(101.9)
  w.m:OnGCDStart(102, 1, w.u.GCD_SOURCE_DIRECT)
  check(w.m.attributableN == 0, "boundary recovery cannot hide a discarded post-baseline input")
end)

test("segment reset forgets the old eviction watermark", function()
  local w = world(); w:baseline()
  w.m:OnPress(100.8); w.m:OnPress(109)
  w.m:OnSegmentStart(200)
  w.m:OnGCDStart(200, 1, w.u.GCD_SOURCE_DIRECT)
  w.m:OnPress(200.9)
  w.m:OnGCDStart(201, 1, w.u.GCD_SOURCE_DIRECT)
  check(w.m.attributableN == 1 and w.m:GetObservationCounts().incomplete == 0, "new segment has independent input coverage")
end)

test("unbounded reference rejects false unique attribution under bounded bursts", function()
  for seed = 1, 120 do
    local w = world({ pressBufferMax = 100, pressBufferSeconds = 2 }); w:baseline()
    local all = {}
    for i = 1, 50 + seed do
      local t = 100.1 + i * 0.012
      all[#all + 1] = t
      w.m:OnPress(t)
    end
    local count = 0
    for _, t in ipairs(all) do if t >= 100.6 and t <= 101 then count = count + 1 end end
    w.m:OnGCDStart(101, 1, w.u.GCD_SOURCE_DIRECT)
    check(w.m.attributableN == 0 or count == 1, "bounded history cannot claim a unique input disproved by full history")
    check(w.m.pressQueue:Size() <= 100, "burst storage bound")
  end
end)

test("cooldown events calibrate while idle without starting tracking or timers", function()
  local w = world(); w:direct(100); w.now = 100.05
  w:fire("SPELL_UPDATE_COOLDOWN")
  near(w.ns.GCDEstimator.calibrationGCD, 1, "idle direct GCD calibrates duration")
  near(w.ns.GCDEstimator.calibrationSwing, 2, "idle calibration pairs readable attack speed")
  check(not w.ns.state.inSegment and w.m.actualFight == 0, "calibration is not a measurement segment")
  check(#w.timers == 0 and #w.tickers == 0, "idle calibration is event-driven, not polling")
end)

test("first restricted fight can use a prior out-of-combat calibration", function()
  local w = world(); w:direct(100); w.now = 100.05; w:fire("SPELL_UPDATE_COOLDOWN")
  w.now, w.combat = 102, true; w:restricted()
  w.ns:OnCombatStart()
  w.now = 102.1; w:fire("UNIT_SPELLCAST_SUCCEEDED")
  w.now = 102.16; w.timers[#w.timers].callback()
  check(w.m.estimatedStarts == 1 and w.m.directStarts == 0, "first restricted fight retains explicitly estimated fallback")
  check(w.m.cycleData:Size() == 0, "estimated fallback never supplies exact SQW")
end)

test("idle combat events do not calibrate or resume a stopped segment", function()
  local w = world(); w.combat = true; w:direct(100); w.now = 100.05
  local reads = w.reads; w:fire("SPELL_UPDATE_COOLDOWN")
  check(w.reads == reads and w.ns.GCDEstimator.calibrationGCD == nil, "idle combat path does no calibration reads")
end)

test("idle calibration requires an explicit out-of-combat capability", function()
  local w = world(); InCombatLockdown = nil
  w:direct(100); w.now = 100.05
  local reads = w.reads; w:fire("SPELL_UPDATE_COOLDOWN")
  check(w.reads == reads, "missing combat predicate does not authorize idle calibration")
end)

test("idle late or future snapshots cannot be paired with current swing", function()
  for _, age in ipairs({ -0.1, 0.3, 1 }) do
    local w = world(); w:direct(100); w.now = 100 + age; w:fire("SPELL_UPDATE_COOLDOWN")
    check(w.ns.GCDEstimator.calibrationGCD == nil, "only near-start observations calibrate while idle")
  end
end)

test("idle repeated cooldown event does not re-pair swing", function()
  local w = world(); w:direct(100); w.now = 100.05; w:fire("SPELL_UPDATE_COOLDOWN")
  w.swing = 3; w.now = 100.1; w:fire("SPELL_UPDATE_COOLDOWN")
  near(w.ns.GCDEstimator.calibrationSwing, 2, "same-start idle read preserves original pair")
  check(w.ns.GCDEstimator.sampleCount == 1, "same-start idle read is deduplicated")
end)

test("idle restricted values cannot establish calibration", function()
  local w = world(); w:restricted(); w:fire("SPELL_UPDATE_COOLDOWN")
  check(w.ns.GCDEstimator.calibrationGCD == nil, "restricted GCD does not calibrate")
  w:direct(100); w.swing = w.secret; w:fire("SPELL_UPDATE_COOLDOWN")
  check(w.ns.GCDEstimator.calibrationGCD == nil, "restricted swing does not calibrate")
end)

test("malformed minimap positions are repaired before the library consumes them", function()
  for _, value in ipairs({ "broken", true, {}, 0/0, math.huge, -math.huge }) do
    local w = world({ localeOverride = "ruRU", minimap = { minimapPos = value, hide = true } })
    local cfg = w.ns:GetConfig()
    check(w.u.IsFiniteNumber(cfg.minimap.minimapPos), "library position is finite numeric data")
    near(cfg.minimap.minimapPos, 225, "invalid minimap position uses the library default")
    check(cfg.minimap.hide == true and cfg.localeOverride == "ruRU", "valid user preferences survive repair")
  end
end)

test("valid minimap angles normalize without losing position", function()
  for _, value in ipairs({ -90, 90, 450, "270" }) do
    local w = world({ minimap = { minimapPos = value } })
    near(w.ns:GetConfig().minimap.minimapPos, tonumber(value) % 360, "finite position is normalized")
  end
end)

test("reload into combat starts one automatic segment at world readiness", function()
  local w = world(); w.combat = true
  w:fire("PLAYER_ENTERING_WORLD")
  check(w.ns.state.inSegment and w.ns.state.autoCombat, "world entry detects already-active combat")
  local ticker = w.ns.GCDDetector.ticker
  w:fire("PLAYER_ENTERING_WORLD")
  check(w.ns.GCDDetector.ticker == ticker, "repeated world readiness does not reset tracking")
end)

test("world readiness preserves explicit pause and manual ownership", function()
  local w = world(); w.combat = true; w.ns:StartSegment(w.now)
  w:fire("PLAYER_ENTERING_WORLD")
  check(not w.ns.state.autoCombat, "manual running segment retains its stop policy")
  w.ns:PauseSegment(w.now)
  w:fire("PLAYER_ENTERING_WORLD")
  check(not w.ns.state.inSegment and w.ns.state.manualPaused, "world readiness does not undo manual stop")
end)

test("world readiness respects disabled auto-start", function()
  local w = world({ autoStartCombat = false }); w.combat = true
  w:fire("PLAYER_ENTERING_WORLD")
  check(not w.ns.state.inSegment and #w.tickers == 0, "disabled automation stays disabled")
end)

test("system delay does not reuse samples from before a blind boundary", function()
  local w = world(); w:baseline()
  for _ = 1, 6 do
    local ready = w.m.lastReadyTime
    w.m:OnPress(ready - 0.1)
    w.m:OnGCDStart(ready + 0.6, 1, w.u.GCD_SOURCE_DIRECT)
  end
  w.m:BreakContinuity()
  w.m:OnGCDStart(200, 1, w.u.GCD_SOURCE_DIRECT)
  w.m:OnPress(200.9)
  w.m:OnGCDStart(201.2, 1, w.u.GCD_SOURCE_DIRECT)
  near(w.m.cycleLog:Back().delay, 0.18, "old 600ms delay must not erase a new 200ms gap")
end)

test("zero queued delay is valid empirical evidence", function()
  local w = world(); w:baseline()
  for _ = 1, 6 do
    local ready = w.m.lastReadyTime
    w.m:OnPress(ready - 0.1)
    w.m:OnGCDStart(ready, 1, w.u.GCD_SOURCE_DIRECT)
  end
  local ready = w.m.lastReadyTime
  w.m:OnPress(ready - 0.1)
  w.m:OnGCDStart(ready + 0.1, 1, w.u.GCD_SOURCE_DIRECT)
  near(w.m.cycleLog:Back().delay, 0.1, "measured zero must not be replaced by a latency-derived deduction")
end)

test("HUD reports incomplete input without calling it missing or ambiguous", function()
  local w = world(); w:baseline()
  w.m:OnPress(100.8); w.m:OnPress(109)
  w.m:OnGCDStart(109.1, 1, w.u.GCD_SOURCE_DIRECT)
  function w.ns:L(_, fallback) return fallback end
  function w.ns:LT(tag) return tag end
  assert(loadfile("GCDOptimizer_HUD.lua"))("GCDOptimizer", w.ns)
  local snapshot = w.ns.HUD:CollectAnalysis(109.1, false, false)
  check(snapshot.incomplete == 1 and snapshot.unobserved == 0 and snapshot.ambiguous == 0,
    "HUD preserves distinct evidence classes")
  check(snapshot.recommendedMs == nil, "incomplete input does not produce an SQW recommendation")
end)

print(string.format("ingress tests: %d cases, %d assertions, %d failed", cases, assertions, failures))
if failures > 0 then os.exit(1) end
