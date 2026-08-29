#!/usr/bin/env python3
"""Converge the GCD observer to 0.5.2 and remove this one-shot script.

If the prior 0.5.1 migration is still pending, run it in the same guarded
working tree first. Then harden segment-start cleanup, the first auto-combat
sample, secrecy-event handling, and deterministic lifecycle coverage.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

SELF = Path("tools/apply_gcd_lifecycle_0502.py")
WORKFLOW = ".github/workflows/apply-gcd-lifecycle-0502.yml"


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def read(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8", newline="\n")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one occurrence, found {count}: {old!r}")
    write(path, text.replace(old, new, 1))


def toc_version() -> str:
    match = re.search(r"^## Version:\s*(\S+)\s*$", read("GCDOptimizer.toc"), re.M)
    if not match:
        raise RuntimeError("TOC version is missing")
    return match.group(1)


def run_pending_0501() -> None:
    migration = Path("tools/apply_gcd_hardening_0501.py")
    if not migration.exists():
        raise RuntimeError("0.5.0 found but the guarded 0.5.1 migration is missing")

    text = migration.read_text(encoding="utf-8")
    anchor = '    ".github/workflows/apply-gcd-hardening.yml",\n'
    additions = (
        anchor
        + '    ".github/workflows/apply-gcd-hardening-v2.yml",\n'
        + f'    "{WORKFLOW}",\n'
        + f'    "{SELF.as_posix()}",\n'
        + '    "GCD_OBSERVATION_CONTRACT.md",\n'
    )
    if text.count(anchor) != 1:
        raise RuntimeError("0.5.1 migration guard anchor mismatch")
    migration.write_text(text.replace(anchor, additions, 1), encoding="utf-8", newline="\n")
    run("python3", migration.as_posix())


version = toc_version()
if version == "0.5.0-midnight-12.1":
    run_pending_0501()
    version = toc_version()

if version == "0.5.2-midnight-12.1":
    SELF.unlink(missing_ok=True)
    print("0.5.2 already present; removed one-shot script")
    raise SystemExit(0)

if version != "0.5.1-midnight-12.1":
    raise RuntimeError(f"Unsupported starting version: {version}")

replace_once("GCDOptimizer.toc", "## Version: 0.5.1-midnight-12.1", "## Version: 0.5.2-midnight-12.1")
replace_once("GCDOptimizer_Core.lua", 'NS.VERSION = "0.5.1-midnight-12.1"', 'NS.VERSION = "0.5.2-midnight-12.1"')
replace_once(
    "GCDOptimizer_Core.lua",
    "  pollInterval = 0.10,\n",
    "  pollInterval = 0.10,\n  autoInitialGCDMaxAge = 0.50,\n",
)

old_start = '''  CallModule(NS.GCDEstimator, "OnSegmentStart", now)
  CallModule(NS.PressTracker, "Reset")
  CallModule(NS.Metrics, "OnSegmentStart", now)
  CallModule(NS.Integrator, "OnSegmentStart", now)
  CallModule(NS.GCDDetector, "OnSegmentStart", now)
  CallModule(NS.Anchors, "OnSegmentStart", now)
  CallModule(NS.Failures, "OnSegmentStart", now)
  CallModule(NS.HUD, "OnSegmentStart", now)
  if not NS:GetConfig().showHUD then
    CallModule(NS.HUD, "StopTicker")
  end
  return NS.state.inSegment
'''
new_start = '''  -- Start every consumer before Detector performs its initial read. If that
  -- read is restricted/unavailable, OnGCDAccessChanged can now pause a fully
  -- initialized segment and every module receives a matching OnSegmentEnd.
  CallModule(NS.GCDEstimator, "OnSegmentStart", now)
  CallModule(NS.PressTracker, "Reset")
  CallModule(NS.Metrics, "OnSegmentStart", now)
  CallModule(NS.Integrator, "OnSegmentStart", now)
  CallModule(NS.Anchors, "OnSegmentStart", now)
  CallModule(NS.Failures, "OnSegmentStart", now)
  CallModule(NS.HUD, "OnSegmentStart", now)
  if not NS:GetConfig().showHUD then
    CallModule(NS.HUD, "StopTicker")
  end

  -- Detector is last because its first observation may synchronously stop the
  -- segment. Nothing may be started after this call.
  CallModule(NS.GCDDetector, "OnSegmentStart", now)
  if not NS.state.inSegment then return false end
  return true
'''
replace_once("GCDOptimizer_Core.lua", old_start, new_start)

old_reanchor = '''    local segmentStart = NS.state.segmentStart or startTime
    local lead = segmentStart - startTime
    if NS.state.autoCombat and lead > 0 and lead <= 2.0 then
      NS.state.segmentStart = startTime
      CallModule(NS.Metrics, "ReanchorStart", startTime)
      CallModule(NS.Integrator, "ReanchorStart", startTime)
    end
'''
new_reanchor = '''    local segmentStart = NS.state.segmentStart or startTime
    local lead = segmentStart - startTime
    local cfg = NS:GetConfig()
    local maxLead = NS.Util.Clamp(cfg.autoInitialGCDMaxAge or 0.50, 0.10, 1.00)
    if NS.state.autoCombat and lead > 0 and lead <= maxLead then
      NS.state.segmentStart = startTime
      CallModule(NS.Metrics, "ReanchorStart", startTime)
      CallModule(NS.Integrator, "ReanchorStart", startTime)
    end
'''
replace_once("GCDOptimizer_Core.lua", old_reanchor, new_reanchor)

replace_once(
    "GCDOptimizer_GCDDetector.lua",
    "local BACKWARD_RESET_EPSILON = 0.25\n",
    "local BACKWARD_RESET_EPSILON = 0.25\nlocal EARLY_CLOCK_TOLERANCE = 0.05\n",
)

old_prime = '''  if self.needsPrime then
    self.lastCountedStart = startTime
    self.lastCountedDuration = duration
    self.needsPrime = false
    if isInitialPoll and countInitial == true then
      self:_CountStart(startTime, duration)
      return true
    end
    return false
  end
'''
new_prime = '''  if self.needsPrime then
    self.lastCountedStart = startTime
    self.lastCountedDuration = duration
    self.needsPrime = false

    -- PLAYER_REGEN_DISABLED can arrive just after the opener starts its GCD.
    -- Count that boundary only when it is very recent. An older cooldown may
    -- predate combat for unrelated reasons and is primed rather than claimed.
    local age = now - startTime
    local maxAge = self.autoInitialMaxAge or 0.50
    local recentAutoBoundary =
      isInitialPoll
      and countInitial == true
      and age >= -EARLY_CLOCK_TOLERANCE
      and age <= maxAge
      and age <= (duration + EARLY_CLOCK_TOLERANCE)

    if recentAutoBoundary then
      self:_CountStart(startTime, duration)
      return true
    end
    return false
  end
'''
replace_once("GCDOptimizer_GCDDetector.lua", old_prime, new_prime)

old_handler = '''  frame:SetScript("OnEvent", function()
    if not self.inSegment then return end
    -- Coalesce event storms into one next-frame read. The watchdog ticker is a
    -- reliability fallback, not the source of timestamp precision: startTime
    -- comes from the cooldown object itself.
    self:_SchedulePoll()
  end)
'''
new_handler = '''  frame:SetScript("OnEvent", function(_, event)
    if not self.inSegment then return end

    if event == "SPELL_SECRECY_CHANGED" then
      -- Close the accessibility boundary synchronously so no extra press can
      -- enter metrics during the one-frame coalescing delay.
      self:_Poll()
      if self.inSegment then self:_SchedulePoll() end
      return
    end

    -- Coalesce ordinary cooldown/cast event storms into one next-frame read.
    -- The watchdog ticker is a reliability fallback; timestamp precision comes
    -- from the accessible cooldown startTime, not callback arrival time.
    self:_SchedulePoll()
  end)
'''
replace_once("GCDOptimizer_GCDDetector.lua", old_handler, new_handler)

old_cfg = '''  local cfg = NS:GetConfig()
  local interval = U.Clamp(cfg.pollInterval or 0.10, 0.05, 0.25)
  local countExisting = NS.state and NS.state.autoCombat and true or false
'''
new_cfg = '''  local cfg = NS:GetConfig()
  local interval = U.Clamp(cfg.pollInterval or 0.10, 0.05, 0.25)
  self.autoInitialMaxAge = U.Clamp(cfg.autoInitialGCDMaxAge or 0.50, 0.10, 1.00)
  local countExisting = NS.state and NS.state.autoCombat and true or false
'''
replace_once("GCDOptimizer_GCDDetector.lua", old_cfg, new_cfg)

replace_once("README.md", "0.5.1-midnight-12.1", "0.5.2-midnight-12.1")
replace_once("README_MIDNIGHT.md", "`0.5.1-midnight-12.1`", "`0.5.2-midnight-12.1`")
replace_once("AGENT_GUIDE.md", "0.5.1-midnight-12.1", "0.5.2-midnight-12.1")

replace_once(
    "README_MIDNIGHT.md",
    "Any non-observable state ends the segment immediately; the first readable cooldown after such a boundary is never reconstructed as historical evidence.\n",
    "Any non-observable state ends the segment immediately; the first readable cooldown after such a boundary is never reconstructed as historical evidence. Detector starts last, after all segment consumers, so a failed initial observation produces a balanced start/end lifecycle rather than half-started modules.\n",
)
replace_once(
    "README_MIDNIGHT.md",
    "Exact start timing comes from the accessible cooldown `startTime`, not callback arrival time.\n",
    "Exact start timing comes from the accessible cooldown `startTime`, not callback arrival time. `SPELL_SECRECY_CHANGED` is checked synchronously; ordinary cooldown events remain coalesced.\n",
)

replace_once(
    "AGENT_GUIDE.md",
    "- A pre-existing cooldown is primed but not counted for manual starts; the first auto-combat GCD may reanchor Metrics and Integrator by at most two seconds.\n",
    "- A pre-existing cooldown is primed but not counted for manual starts. Auto-combat may count/reanchor only a recent initial cooldown, bounded by `autoInitialGCDMaxAge` (default 0.50 s); older pre-combat cooldowns are primed.\n- Start all segment consumers before Detector. Detector must remain last because its initial accessibility check may synchronously end the segment.\n",
)

changelog = read("CHANGELOG.md")
entry = '''# Changelog

## 0.5.2-midnight-12.1 — 2026-08-29

### Lifecycle and boundary accuracy

- Start all segment consumers before Detector so an inaccessible initial GCD observation produces balanced start/end callbacks.
- Make Detector the final segment-start step because its policy check may synchronously stop tracking.
- Check `SPELL_SECRECY_CHANGED` synchronously before accepting another input timestamp.
- Count/reanchor an already-active first auto-combat GCD only when its start is within the configurable 0.50-second boundary; older pre-combat cooldowns are primed instead.
- Add deterministic Core lifecycle coverage and stale pre-combat GCD coverage.

'''
if not changelog.startswith("# Changelog\n\n## 0.5.1"):
    raise RuntimeError("Unexpected changelog version before 0.5.2")
write("CHANGELOG.md", entry + changelog[len("# Changelog\n\n"):])

contract = read("tools/check_contract.py")
contract = contract.replace("0.5.1-midnight-12.1", "0.5.2-midnight-12.1")
anchor = 'assert "ReadGCDCooldownState" in detector\n'
addition = anchor + '''
core_start = core.index('CallModule(NS.GCDEstimator, "OnSegmentStart", now)')
core_hud = core.index('CallModule(NS.HUD, "OnSegmentStart", now)', core_start)
core_detector = core.index('CallModule(NS.GCDDetector, "OnSegmentStart", now)', core_start)
assert core_start < core_hud < core_detector
assert "autoInitialGCDMaxAge = 0.50" in core
assert 'event == "SPELL_SECRECY_CHANGED"' in detector
'''
if contract.count(anchor) != 1:
    raise RuntimeError("contract checker anchor mismatch")
write("tools/check_contract.py", contract.replace(anchor, addition, 1))

harness = read("tests/test_gcd_observation.lua")
old_auto = '''-- Auto-combat startup may count the already-active combat-triggering GCD.
D:OnSegmentEnd()
starts = {}
NS.state.inSegment = true
NS.state.autoCombat = true
cooldown = { startTime = 20.0, duration = 1.5, isEnabled = true, modRate = 1 }
now = 20.05
D:OnSegmentStart()
assert(#starts == 1)
assert(starts[1].startTime == 20.0)
'''
new_auto = '''-- Auto-combat startup may count a recent combat-triggering GCD.
D:OnSegmentEnd()
starts = {}
NS.state.inSegment = true
NS.state.autoCombat = true
cooldown = { startTime = 20.0, duration = 1.5, isEnabled = true, modRate = 1 }
now = 20.05
D:OnSegmentStart()
assert(#starts == 1)
assert(starts[1].startTime == 20.0)

-- An older active cooldown at combat entry is pre-combat/ambiguous and primes.
D:OnSegmentEnd()
starts = {}
NS.state.inSegment = true
NS.state.autoCombat = true
cooldown = { startTime = 30.0, duration = 1.5, isEnabled = true, modRate = 1 }
now = 30.80
D:OnSegmentStart()
assert(#starts == 0)

cooldown = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
now = 31.50
D:_Poll()
cooldown = { startTime = 31.60, duration = 1.0, isEnabled = true, modRate = 1 }
now = 31.61
D:_Poll()
assert(#starts == 1)
'''
if harness.count(old_auto) != 1:
    raise RuntimeError("GCD harness auto-boundary anchor mismatch")
write("tests/test_gcd_observation.lua", harness.replace(old_auto, new_auto, 1))

LIFECYCLE = r'''-- Core lifecycle regression: Detector may reject the initial observation
-- synchronously, but every started consumer must still receive OnSegmentEnd.

local now = 100
function GetTime() return now end
function CreateFrame()
  return {
    RegisterEvent = function() end,
    RegisterUnitEvent = function() end,
    SetScript = function() end,
  }
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
_G.GCDOptimizerDB = { showHUD = false }

local NS = {}
local counts = {}
local function module(name)
  counts[name] = { starts = 0, ends = 0 }
  return {
    Init = function() end,
    Reset = function() end,
    OnSegmentStart = function() counts[name].starts = counts[name].starts + 1 end,
    OnSegmentEnd = function() counts[name].ends = counts[name].ends + 1 end,
  }
end

NS.Util = {
  Clamp = function(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
  end,
  Deque = { New = function() return {} end },
}
NS.GCDEstimator = module("estimator")
NS.PressTracker = module("press")
NS.Metrics = module("metrics")
NS.Integrator = module("integrator")
NS.Anchors = module("anchors")
NS.Failures = module("failures")
NS.HUD = module("hud")
NS.HUD.frame = { SetShown = function() end, HookScript = function() end }
NS.HUD.StopTicker = function() end
NS.Options = { Init = function() end }
NS.Minimap = { Init = function() end }
NS.GCDDetector = module("detector")
NS.GCDDetector.OnSegmentStart = function()
  counts.detector.starts = counts.detector.starts + 1
  NS:OnGCDAccessChanged(false, now, "restricted")
end

local chunk = assert(loadfile("GCDOptimizer_Core.lua"))
chunk("GCDOptimizer", NS)

local started = NS:StartSegment(now)
assert(started == false)
assert(NS.state.inSegment == false)
assert(NS.state.stopReason == "gcd-restricted")

for _, name in ipairs({ "estimator", "metrics", "integrator", "anchors", "failures", "hud", "detector" }) do
  assert(counts[name].starts == 1, name .. " start count")
  assert(counts[name].ends == 1, name .. " end count")
end

print("core lifecycle harness: OK")
'''
write("tests/test_core_lifecycle.lua", LIFECYCLE)

validate = read(".github/workflows/validate.yml")
old_step = '''      - name: Deterministic GCD harness
        run: lua5.1 tests/test_gcd_observation.lua
      - name: Whitespace errors
'''
new_step = '''      - name: Deterministic GCD harness
        run: lua5.1 tests/test_gcd_observation.lua
      - name: Core lifecycle harness
        run: lua5.1 tests/test_core_lifecycle.lua
      - name: Whitespace errors
'''
if validate.count(old_step) != 1:
    raise RuntimeError("validation workflow anchor mismatch")
write(".github/workflows/validate.yml", validate.replace(old_step, new_step, 1))

with Path("todo.md").open("a", encoding="utf-8", newline="\n") as handle:
    handle.write('''
## 0.5.2 follow-up validation

- [x] Balance module lifecycle when the initial GCD read is non-observable.
- [x] Check secrecy changes synchronously.
- [x] Exclude stale pre-combat cooldowns from the first auto-combat GCD count.
- [x] Add deterministic Core lifecycle and stale-boundary tests.
- [ ] Implement ambiguity-aware press attribution before treating input lead as exact evidence.
- [ ] Run the full current-client matrix in issue #1.
''')

SELF.unlink(missing_ok=True)
print("0.5.2 lifecycle hardening applied")
