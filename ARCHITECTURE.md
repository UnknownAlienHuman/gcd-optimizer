# Architecture

## Ownership

`GCDOptimizer_Core.lua` is the composition root. It owns configuration migration, segment lifecycle, combat automation, HUD visibility, and the sole `/gcdopt` dispatcher.

`GCDOptimizer_Util.lua` is the only low-level reader for restriction-sensitive GCD and attack-speed values. Detector, estimator, metrics, and HUD consume ordinary outputs from that boundary.

## Data flow

```text
C_Spell.GetSpellCooldown(61304)
  ├─ ordinary start/duration/modRate ─► DIRECT_EXACT
  ├─ active flag + restricted numbers ─► candidate fallback gate
  └─ inactive flag ────────────────────► reject off-GCD success

UnitAttackSpeed(player)
  + last direct GCD/swing pair ────────► ESTIMATED_SWING duration

UNIT_SPELLCAST_SUCCEEDED
  └─ local timestamp only
     + confirmed active generic GCD ───► ESTIMATED_SWING start

secure action post-hooks ──────────────► local press timestamps

accepted starts + timestamps ─────────► Metrics
  ├─ cadence (exact or explicitly estimated)
  └─ exact input evidence only when:
       previous source = DIRECT_EXACT
       current source  = DIRECT_EXACT
       candidate count = 1

Metrics + Integrator + Failures ───────► HUD
```

## Observation classes

### `DIRECT_EXACT`

All timing fields are accessible, finite, positive, and normalized by `modRate`. This is the only authoritative start source.

### `ESTIMATED_SWING`

Direct numerical timing is unavailable, generic-GCD activity is confirmed, and a valid direct/swing calibration exists. It preserves approximate cadence but is excluded from exact latency/SQW evidence.

### `CACHED_LOW_CONFIDENCE`

Only a last stable/default duration is available. It is display-only: no start, no possible-GCD integration, no latency claim.

## Deduplication

The detector delays event fallback briefly, deduplicates repeated direct starts, and upgrades a nearby estimated start when direct timing arrives later. Upgrade changes the source without adding a second observed GCD. Same-cycle source priority is monotonic (`DIRECT_EXACT` cannot be overwritten by `ESTIMATED_SWING`), and unchanged exact polls do not propagate redundant HUD refreshes.

## Lifecycle

Detector and HUD timers are segment-scoped and cancelled before replacement and at segment end/reset. Estimator calibration survives ordinary segment resets but is invalidated by equipment or specialization changes.

## Persistence

Only user configuration is stored in `GCDOptimizerDB`. Transient timing, source labels, presses, events, and failures are never serialized.
