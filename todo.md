# GCD Optimizer — release checklist

## Preserved 12.1 work

- [x] Target Retail 12.1.0 / Interface `120100`.
- [x] Initialize `GCDOptimizer_GCDDetector` from Core.
- [x] Keep one production `/gcdopt` dispatcher.
- [x] Preserve compatible SavedVariables through schema migration.
- [x] Keep press hooks timestamp-only.
- [x] Remove combat-log and raw UI-error failure inference.
- [x] Remove obsolete `GetMouseFocus` use.
- [x] Keep detector/HUD work segment-scoped.

## Regression repair

- [x] Restore the known `baseSwing/currentSwing` GCD estimator.
- [x] Restore the event-derived candidate-start fallback.
- [x] Remove the pending direct-only migration workflow/script.
- [x] Correct direct-only documentation.

## Required hardening

- [ ] Centralize accessibility checks for both `61304` numeric fields and `UnitAttackSpeed` without removing either source.
- [ ] Preserve swing calibration across reset/start boundaries correctly.
- [ ] Detect weapon swaps and attack-speed-only modifiers; recalibrate or downgrade confidence.
- [ ] Calibrate one-second base-GCD specs rather than silently using `1.5`.
- [ ] Distinguish `DIRECT_EXACT`, `ESTIMATED_SWING`, and `CACHED_LOW_CONFIDENCE` in metric records and HUD/debug output.
- [ ] Prevent off-GCD `UNIT_SPELLCAST_SUCCEEDED` events from becoming exact GCD cycles.
- [ ] Validate instant, cast-time, channelled, and empowered event timing separately.
- [ ] Exclude estimated and ambiguous samples from exact latency/SQW recommendations.
- [ ] Add deterministic tests for direct-to-estimated transitions and duplicate suppression.

## Current-client release gate

Record exact version, build, Interface, date, content type, restriction state, and taint state.

- [ ] Outside combat: probe `61304` policy and numeric accessibility.
- [ ] Open-world combat: repeat the probe and capture attack-speed accessibility.
- [ ] Encounter and Mythic+: repeat.
- [ ] Arena and battleground: repeat.
- [ ] Trigger/observe `SPELL_SECRECY_CHANGED`.
- [ ] Test ordinary and one-second-GCD specs.
- [ ] Test weapon swaps, haste changes, and attack-speed-only effects.
- [ ] Mix off-GCD actions into every rotation.
- [ ] Compare exact/estimated cycle counts against a recorded manual timeline.
- [ ] Verify login, `/reload`, controls, minimap, persistence, ticker cleanup, and no Lua/taint errors.

Issues #1 and #5 are release blockers. Do not package a release until both evidence and behavior are resolved.
