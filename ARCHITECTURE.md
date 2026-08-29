# Architecture

## Composition root

`GCDOptimizer_Core.lua` loads last and owns `GCDOptimizerDB`, schema/default migration, module initialization, segment lifecycle, combat automation, HUD visibility, and the sole `/gcdopt` dispatcher.

## Timing data flow

```text
C_Spell.GetSpellCooldown(61304)
        │
        ├── ordinary numeric fields ──────────────► Detector: DIRECT_EXACT
        │                                              │
        │                                              ▼
        │                                            Metrics
        │
        └── Secret/unusable numeric fields
                      │
UnitAttackSpeed(player) ─► calibrated ratio ─► Estimator: ESTIMATED_SWING
                      │                             ▲
UNIT_SPELLCAST_SUCCEEDED ─► candidate timestamp ───┘

secure action post-hooks ─► local press timestamps ─► Metrics ─► HUD
Estimator ─► Integrator ──────────────────────────────────────► HUD
player failure events ─► payload-free Failures ───────────────► HUD
overlay glow events ─► bounded Anchors diagnostics
```

## Evidence classes

### DIRECT_EXACT

Accessible `61304` start/duration values. These are the preferred source and can replace an event estimate for the same cycle.

### ESTIMATED_SWING

Direct numbers are unusable, but accessible attack-speed calibration and local event timing remain. This preserves functionality under the project's reported Midnight combat behavior. It is approximate and must be labeled.

### CACHED_LOW_CONFIDENCE

Neither current direct timing nor swing speed can be used. The last stable duration may keep the UI coherent, but no exact start or latency claim may be manufactured.

The current restored implementation does not yet attach these labels to every metric record; issue #5 owns that hardening.

## Security boundary

Both `C_Spell.GetSpellCooldown(61304)` and `UnitAttackSpeed("player")` are restriction-sensitive sources. A documented spell whitelist does not replace per-use accessibility checks. A successful `pcall` does not declassify data.

Input hooks retain timestamps only. Failure tracking does not parse combat log or UI-error payloads. Transient spellcast payloads used by the fallback detector must not flow into SavedVariables or general feature state.

## Known approximation risks

- attack speed can diverge from GCD haste;
- weapon swaps alter swing speed independently of haste;
- a default `1.5` base GCD is wrong for some specs;
- successful off-GCD actions can reach the fallback detector;
- success-event timing differs among instant, cast-time, channelled, and empowered spells;
- exact and estimated samples are not yet separated in recommendations.

## Lifecycle

Core initializes modules once and starts/stops segment-scoped work. Detector and HUD timers must be cancelled on reset/end. Direct polling and event fallback must deduplicate the same GCD rather than creating two metric cycles.
