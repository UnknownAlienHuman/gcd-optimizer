# Changelog

## Unreleased correction — 2026-08-29

### GCD regression repair

- Restored the original `UnitAttackSpeed`-calibrated GCD estimator after the 12.1 pass incorrectly removed it.
- Restored the `UNIT_SPELLCAST_SUCCEEDED` candidate-start fallback for combat contexts where numerical `61304` timing cannot be used.
- Preserved unrelated 12.1 fixes: detector initialization, single command ownership, SavedVariables migration, payload-free press/failure tracking, and obsolete API cleanup.
- Removed an unexecuted direct-only migration workflow and its one-shot script.
- Opened issue #5 to resolve the conflict between Blizzard's documented `61304` whitelist and the project's combat runtime history.

### Documentation correction

- Retracted the claim that direct `61304` timing is sufficient in every supported context.
- Documented direct, swing-estimated, and cached-low-confidence observation classes.
- Marked off-GCD event inference, one-second-GCD calibration, weapon swaps, and source-confidence separation as open correctness work.

## 0.5.0-midnight-12.1 — 2026-08-27

### Compatibility and infrastructure

- Updated the addon to Retail 12.1.0 / Interface `120100`.
- Pinned review to Blizzard UI source build `12.1.0.69497`, commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`.
- Fixed Core bootstrap so `GCDOptimizer_GCDDetector:Init()` registers its events.
- Centralized lifecycle, HUD visibility, command dispatch, and compatible SavedVariables migration.
- Unified production slash commands under one `/gcdopt` handler.
- Excluded the developer test harness from the production TOC.

### Security and cleanup

- Made action press tracking timestamp-only.
- Removed combat-log and raw `UI_ERROR_MESSAGE` failure-reason inference.
- Bounded overlay diagnostics and removed obsolete `GetMouseFocus` use.

### Superseded GCD change

The initial 0.5.0 pass removed attack-speed reconstruction and attempted a direct-only `61304` detector. That decision was reverted by the 2026-08-29 correction above because it discarded an intentional combat fallback without named-build runtime proof.
