# Architecture

## Bootstrap and ownership

`GCDOptimizer_Core.lua` loads last and is the composition root. It owns `GCDOptimizerDB`, schema/default migration, module initialization, segment lifecycle, combat autostart/autostop, HUD visibility, and the sole `/gcdopt` dispatcher.

The production TOC excludes `GCDOptimizer_Test.lua`; the developer harness uses the separate `/gcdopttest` command when manually loaded.

## Data flow

```text
secure action post-hooks
        │ timestamp only
        ▼
 PressTracker ───────────────► Metrics ───────────────► HUD
                                     ▲                   ▲
                                     │                   │
 C_Spell cooldown 61304 ─► Util gate ─► Detector ───────┤
                                     │                   │
                                     └► Estimator ─► Integrator

 UNIT_SPELLCAST_FAILED(*) ─► Failures (timestamp only) ─► HUD
 overlay glow show/hide ───► Anchors (bounded diagnostic ring)
```

## Security boundary

`GCDOptimizer_Util.lua:ReadSpellCooldown` is the only direct spell-cooldown boundary. It verifies accessibility before inspecting, comparing, formatting, indexing, or retaining returned fields. The detector and estimator consume only ordinary numeric values from this boundary.

A successful spellcast schedules a cooldown read but never becomes an inferred GCD start. Input and failure callbacks discard their payloads. No combat-log, UI-error-text, aura, target, resource, or unit-stat reconstruction path exists.

## State

Persistent:

- `GCDOptimizerDB`: compatible configuration only;
- `__addonVersion`: release metadata;
- `__schemaVersion`: migration contract.

Transient:

- detector/estimator state;
- press timestamps;
- metric deques and segment aggregates;
- failure timestamps;
- overlay diagnostic ring;
- UI frame and ticker state.

Transient combat observations must not be copied into SavedVariables.

## Timing ownership

- Detector establishes confirmed GCD starts and observed durations.
- Estimator supplies the last accessible duration/fallback.
- Integrator computes possible intervals from the estimator.
- Metrics classifies input and accounts for gaps.
- HUD renders snapshots; it does not discover combat state.

## Lifecycle

Core initializes modules once, resets a clean baseline, then starts segments manually or on combat entry. A manual start primes an already-active cooldown without counting it; an auto-combat start may reanchor the segment to the triggering GCD. Detector and HUD timers exist only while needed and are cancelled on reset/end. `ResetAndContinue` clears samples without changing whether the segment was manually or automatically running.
