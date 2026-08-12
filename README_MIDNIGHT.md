# GCD Optimizer — Midnight port notes (v0.2.0-midnight)

## What changed (problem-driven)

Midnight (12.0) introduces **Secret Values** and removes key combat APIs (notably combat log access).
Any arithmetic/comparison on a Secret Value throws a Lua error. Therefore, anything that used to
compute timing from cooldowns/haste in combat must be guarded.

This port implements a **multi-source GCD duration estimator** designed to keep the addon running
even when some fields become Secret.

## New module: `GCDOptimizer_GCDEstimator.lua`

Priority order for a safe numeric `predictedGCD`:

1. **Direct GCD cooldown duration** via spell 61304 if readable and non-Secret.
2. **Auto-attack swing speed ratio**:
   - record baseline swing speed out-of-combat (`baseSwing`)
   - infer haste multiplier as `baseSwing / currentSwing`
   - estimate `GCD ~= baseGCD / hasteMult`, clamped to [0.75, 1.5]
3. **Observed cast-to-cast delta correction**:
   - uses `UNIT_SPELLCAST_SUCCEEDED` timestamps (GetTime), which are non-Secret
   - smooths with EWMA, used only to nudge the estimate downward (never upward)
4. **Fallback to last stable value**.

## GCD starts in Midnight

`GCDOptimizer_GCDDetector.lua` now also listens to:

- `UNIT_SPELLCAST_SUCCEEDED` for `unit=="player"`

This is used as the primary "GCD start" signal (instead of combat log and/or cooldown polling).
If cooldown polling is still readable, it continues to run and can refine duration.

## Secret-safe failure tracking

`GCDOptimizer_Failures.lua`:
- skips `COMBAT_LOG_EVENT_UNFILTERED` registration on interface >= 120000
- guards `UI_ERROR_MESSAGE` text parsing: if the message is Secret, it is recorded as `SECRET_UI_ERROR`
  and no string matching is attempted.

## Manual test harness

`GCDOptimizer_Test.lua` provides:

- `/gcdopt test` — runs a pure-Lua simulation of the estimator (no game APIs required)
- `/gcdopt debug` — prints estimator snapshot

Recommended usage: out of combat.

## Next steps (planned but not implemented here)

- Add optional calibration UI: show baselineGCD/baseSwing and "recalibrate" button.
- Segment-level confidence scoring: which source dominated the estimate (cooldown vs swing vs fallback).
- Exportable debug logs (SavedVariables ring buffer) for post-fight analysis without combat log.


## Anchor system (overlay fade -> proc consumption)

- Module: `GCDOptimizer_Anchors.lua`
- Records `SPELL_ACTIVATION_OVERLAY_*` show/hide plus `UNIT_SPELLCAST_*` and local presses.
- Primary heuristic: **overlay hide** correlated with nearby `UNIT_SPELLCAST_SUCCEEDED` of allowed consumer spells.
- Configure rules in `GCDOptimizerDB.anchors.rules` (per-spec) after verification via `/eventtrace`.
