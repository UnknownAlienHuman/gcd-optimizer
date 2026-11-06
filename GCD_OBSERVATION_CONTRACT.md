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

The source is always `ESTIMATED_SWING`. Equipment/spec changes invalidate the calibration. While idle and explicitly outside combat, `SPELL_UPDATE_COOLDOWN` may calibrate a direct GCD/swing pair observed within 250 ms of its start. This creates no segment, metric or timer; inaccessible or stale observations do not calibrate.

## Cached state

A last stable/default duration may keep the HUD readable, but `CACHED_LOW_CONFIDENCE` must not:

- create a GCD start;
- integrate possible GCDs;
- create lost/latency/SQW samples;
- be presented as observed timing.

## Input attribution

For each exact-to-exact cycle, first require complete retained press history for the attribution window. Age/capacity eviction and boundary clearing retain a timestamp watermark. An overlapping window is `incomplete_input`, separately counted and excluded from latency/SQW and absence-of-input gap diagnostics. Ordinary cadence counts remain valid. With complete history:

- zero candidates → `unobserved_input`;
- one candidate → eligible exact queue/late attribution;
- more than one → `ambiguous_multi_press`.

Unobserved and ambiguous cycles remain useful for aggregate cadence/press-density diagnostics, but are excluded from exact latency and SQW recommendations.

## Analysis windows

SQW evidence is bounded by the latest `statWindowN` accepted starts, not the latest successful attributions alone. Ambiguous, unobserved and estimated starts age earlier samples. The system-delay estimate, lead buffer and candidate search use this same fresh sample set; measured zero delay is valid; late-only samples do not establish a usable queue window. Search includes its upper bound even when the step does not divide the range.

Live verdicts use a ten-second window and at least five attributable cycles in that window after the latest continuity boundary. Missing/old hook evidence is not inactivity, and ambiguity is not a player-error verdict. Final verdicts use the closed segment, not later combat or elapsed wall time.

Full-segment counts and gap-time totals are cumulative. Rolling records remain bounded to 600 cycles; final-report percentile distributions use the latest `statWindowN` samples in each category, not whole-fight quantiles. Queue-hit and late-input shares divide by attributable cycles; queue coverage divides by all exact cycles.

## Observation continuity

Restricted, unavailable, malformed, and `SPELL_SECRECY_CHANGED` observations break exact adjacency without stopping the segment or erasing accepted counts. Discard pending fallback inference on policy invalidation and input/SQW evidence spanning the boundary. Preserve detector identity for deduplication.

A recovered same-start observation does not reopen the old exact link. A new accepted start establishes the next baseline. An estimate-to-direct upgrade may improve that start's source, but must not retroactively analyze a cycle crossing a blind interval. Ordinary inactive observations do not break continuity.

## Capacity accounting

Detector observations, not UI reads, own the integration rate. Cached/unavailable observations have zero rate; usable swing-derived rates remain estimates. Keep rate-change history bounded and checkpoint the latest meaningful action for the final idle-tail cut. After segment end, the integral is immutable. Showing, hiding, or refreshing the HUD must not change it.

## Upgrade rule

If direct timing arrives within the upgrade window of an accepted estimate, replace the estimate's source/timing in place. Do not add a second cycle. Within one deduplicated cycle, source quality is monotonic: estimated timing cannot overwrite an exact duration. An unchanged exact poll is not a refresh event. Compare duration corrections against the last forwarded value so sub-threshold steps accumulate. A material same-start duration correction invalidates its original swing pair; only a fresh exact start can recalibrate it.

## Runtime status

The code contract is deterministic; live behavior remains build/context dependent. Record results in `GCD_RUNTIME_EVIDENCE.md`.
