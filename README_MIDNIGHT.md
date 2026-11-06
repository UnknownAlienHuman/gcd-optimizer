# GCD Optimizer — Retail 12.1.5 engineering notes

## Baseline

| Field | Value |
| --- | --- |
| Addon version | `0.6.0-midnight-12.1.5` |
| Patch contract | Retail `12.1.5` |
| Interface | `120105` |
| KB source contract | selected 12.1.5 build family |
| Review date | 2026-11-06 |

## Why the hybrid model remains

Project history reports combat contexts where numerical `61304` fields became restricted. Blizzard-origin documentation also describes a GCD whitelist. The conflict is not resolved by deleting either evidence path.

The implementation therefore prefers direct ordinary timing, retains a guarded swing-calibrated fallback, and labels every accepted start. A named-build runtime matrix remains mandatory.

## Direct path

`GCDOptimizer_Util.lua` centralizes the only cooldown read. It gates the table and each consumed field, normalizes `duration / modRate`, and returns `DIRECT_EXACT` only for valid ordinary numbers.

`isActive` is used as an activity gate. It is not treated as numerical timing.

## Estimated path

The estimator records the first accessible main-hand swing speed paired with each new direct GCD. Repeated polls of that same cooldown do not recalibrate against a later attack-speed state. This calibrates one-second and ordinary GCD profiles without class/spec hardcoding.

When numerical timing is unavailable:

```text
estimatedGCD = calibratedGCD * currentSwing / calibratedSwing
```

A player success event can supply the local candidate timestamp only after the generic GCD activity flag confirms that a GCD is active. Weapon/spec changes invalidate calibration. Attack-speed-only effects remain an approximation risk and are visible through the `ESTIMATED_SWING` label.

## Metrics boundary

Cadence may include explicitly estimated starts. Exact input analysis does not.

Latency and SQW samples require:

- previous and current starts both `DIRECT_EXACT`;
- exactly one local press in the attribution window.

Zero candidates are unobserved, not proof of inactivity. Multiple candidates are ambiguous, not a license to select one. The attribution window is also bounded strictly after the previous GCD start, so an extreme CVar cannot reuse the action that began the previous cycle.

## Timer ownership

- Detector owns one segment ticker and at most one deferred fallback timer.
- HUD owns one segment ticker.
- Replacement and teardown cancel the prior handle.
- Unchanged same-start exact polls do not trigger HUD refreshes; only material duration changes do.

## Validation

`tests/test_runtime.lua` covers the deterministic source model. Live-client probes are still required for open world, encounter/Mythic+, arena, battleground, ordinary/one-second profiles, haste/weapon changes, off-GCD mixtures, and `SPELL_SECRECY_CHANGED`.
