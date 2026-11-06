# GCD observation contract

## Purpose

Produce the strongest available GCD observation without converting restricted or ambiguous evidence into exact data.

## Direct observation

For spell `61304`:

1. call `C_Spell.GetSpellCooldown` inside an error-containment boundary;
2. establish table/field accessibility;
3. read the NeverSecret `isActive` field when available;
4. reject inactive cooldowns;
5. gate `startTime`, `duration`, and `modRate` before any use;
6. require finite positive numbers;
7. normalize wall duration as `duration / modRate`;
8. emit `DIRECT_EXACT` and deduplicate by start time.

No documented whitelist replaces the runtime accessibility checks.

## Estimated fallback

`UNIT_SPELLCAST_SUCCEEDED` does not prove that an action triggered the GCD. It only schedules one short deferred observation.

An estimated start is accepted only when all conditions hold:

- the generic GCD `isActive` field confirms activity;
- direct numerical fields remain unavailable;
- a direct GCD/swing calibration exists;
- current `UnitAttackSpeed("player")` is accessible and valid;
- cadence gating rejects duplicates and too-early continuous-active events inside the same GCD.

Duration is:

```text
calibratedGCD * currentSwing / calibratedSwing
```

The source is always `ESTIMATED_SWING`. Equipment/spec changes invalidate the calibration.

## Cached state

A last stable/default duration may keep the HUD readable, but `CACHED_LOW_CONFIDENCE` must not:

- create a GCD start;
- integrate possible GCDs;
- create lost/latency/SQW samples;
- be presented as observed timing.

## Input attribution

For each exact-to-exact cycle, consider local presses in the attribution window:

- zero candidates → `unobserved_input`;
- one candidate → eligible exact queue/late attribution;
- more than one → `ambiguous_multi_press`.

Unobserved and ambiguous cycles remain useful for aggregate cadence/press-density diagnostics, but are excluded from exact latency and SQW recommendations.

## Upgrade rule

If direct timing arrives within the upgrade window of an accepted estimate, replace the estimate's source/timing in place. Do not add a second cycle. Within one deduplicated cycle, source quality is monotonic: estimated timing cannot overwrite an exact duration. An unchanged exact poll is not a refresh event.

## Runtime status

The code contract is deterministic; live behavior remains build/context dependent. Record results in `GCD_RUNTIME_EVIDENCE.md`.
