# Changelog

## 0.5.0-midnight-12.1 — 2026-08-27

### Compatibility

- Updated the addon to Retail 12.1.0 / Interface `120100`.
- Pinned engineering review to Blizzard UI source build `12.1.0.69497`, commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`.

### Correctness

- Fixed Core bootstrap so `GCDOptimizer_GCDDetector:Init()` actually registers its events.
- Replaced successful-cast inference with authoritative reads of the GCD dummy cooldown (`61304`).
- Removed the unavailable `C_Spell.DoesSpellTriggerGlobalCooldown` dependency.
- Prevented off-GCD abilities from being counted as GCD starts.
- Prevented manual segments from claiming a GCD that was already running before tracking began; auto-combat segments reanchor to the triggering GCD start.
- Removed unreliable `UnitAttackSpeed` haste reconstruction.

### Secret-value and taint safety

- Added a centralized accessibility gate before cooldown fields are inspected or retained.
- Changed press tracking to retain timestamps only; hook arguments are discarded.
- Removed combat-log and `UI_ERROR_MESSAGE` failure-reason inference.
- Changed failure tracking to payload-free player failure counts with generic categorization.
- Restricted anchor diagnostics to accessibility-gated overlay glow events and ordinary local press timestamps.
- Removed obsolete `GetMouseFocus` use from the settings panel.

### Lifecycle and performance

- Reduced default detector polling from `0.02` to `0.05` seconds.
- Ensured detector timers are segment-scoped and cancelled on reset/end.
- Centralized initialization, lifecycle, HUD visibility, and command dispatch in Core.

### User-facing behavior

- Unified all production slash commands under one `/gcdopt` handler.
- Removed slash-command shadowing by Minimap and Test modules.
- Excluded the developer test harness from the production TOC; its manual command is `/gcdopttest`.
- Added minimap icon show/hide subcommands.
- Changed SavedVariables upgrades to preserve compatible settings through explicit schema migration.

### Verification status

- Static syntax and forbidden-symbol checks are required and recorded with this update.
- Current-client combat validation remains open in GitHub issue #1; this source must not be treated as a packaged release until that smoke matrix is complete.
