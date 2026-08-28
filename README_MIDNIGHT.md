# GCD Optimizer — Retail 12.1 engineering notes

## Release baseline

| Field | Value |
| --- | --- |
| Addon version | `0.5.0-midnight-12.1` |
| WoW patch contract | Retail `12.1.0` |
| Interface | `120100` |
| Reviewed live source | `12.1.0.69497` |
| Blizzard source commit | `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4` |
| Review date | 2026-08-27 |

The implementation follows the repository at [wow-addon-engineering-kb](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb), particularly its 12.1 migration guide, security model, performance guidance, and spell-secrecy registry.

## 1. GCD observation contract

`GCDOptimizer_Util.lua` owns the only spell-cooldown read boundary:

1. call `C_Spell.GetSpellCooldown(61304)`;
2. gate the returned object and both numeric fields with `canaccessallvalues`/`canaccessvalue` before any use;
3. accept only ordinary positive numbers;
4. collapse inaccessible, inactive, missing, or malformed data to `nil`.

`GCDOptimizer_GCDDetector.lua` polls that boundary at 20 Hz by default. `UNIT_SPELLCAST_SUCCEEDED` merely requests an immediate read and a zero-delay follow-up read. The event payload is discarded, and a successful cast is never assumed to trigger the GCD.

A manual segment that begins during an already-running GCD primes that cooldown without counting activity from before the user started tracking. An auto-combat segment counts the combat-triggering GCD and reanchors the segment to its real cooldown start when `PLAYER_REGEN_DISABLED` arrived slightly later.

This fixes two older design errors:

- the previous detector depended on `C_Spell.DoesSpellTriggerGlobalCooldown`, which is not part of the current generated API contract;
- its conservative fallback counted every successful cast, including off-GCD abilities.

The detector is now explicitly initialized by Core. The previous build called `Reset()` but never `Init()`, so its event frame was never registered.

## 2. Duration estimation

`GCDOptimizer_GCDEstimator.lua` no longer derives haste from `UnitAttackSpeed`. Both attack speed and spell haste are restriction-sensitive unit-stat APIs, and weapon-speed ratios are not a reliable cross-class GCD model.

The estimator now uses:

1. the current accessible duration of spell `61304`;
2. the last ordinary duration observed in this client session;
3. `1.5` seconds only as the initial fallback before the first readable sample.

The GCD dummy spell is listed in historical Midnight exemptions, but exemptions are data-driven and may change through hotfixes. The addon therefore checks accessibility on every read rather than treating `61304` as a permanent whitelist entry.

## 3. Input boundary

`GCDOptimizer_PressTracker.lua` installs secure post-hooks for supported player-action paths. Every hook callback has zero parameters and records only `GetTime()`.

The following data is deliberately discarded:

- action slots;
- spell IDs and names;
- macro text;
- item IDs;
- targets and unit tokens;
- cast GUIDs.

`GCDOptimizer_Metrics.lua` continues to receive its existing record shape, but only the timestamp is populated. This preserves queue/late classification without allowing protected payloads into feature state.

## 4. Failure diagnostics

The 12.1 implementation does not register `COMBAT_LOG_EVENT_UNFILTERED` and does not parse `UI_ERROR_MESSAGE`. Both approaches are unsuitable as a general restricted-combat inference channel.

`GCDOptimizer_Failures.lua` listens only for player `UNIT_SPELLCAST_FAILED` and `UNIT_SPELLCAST_FAILED_QUIET`, ignores all payload fields, deduplicates paired notifications, and records timestamps. Its public summary shape remains compatible with the HUD, but failures are categorized as `OTH`.

This is intentionally less specific and more trustworthy. A reason taxonomy can be restored only when a current Blizzard contract supplies an accessible source for it.

## 5. Overlay anchors

The optional anchor diagnostic listens only to Blizzard's glow show/hide events:

- `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW`
- `SPELL_ACTIVATION_OVERLAY_GLOW_HIDE`

The overlay spell ID is accessibility-gated before it is compared, indexed, formatted, or stored. Fades may be correlated with a recent ordinary local press timestamp, but the result remains a low-confidence diagnostic and is not used as proof of proc consumption or as a GCD source.

## 6. Commands and production load order

`GCDOptimizer_Core.lua` is the sole owner of `/gcdopt`. The duplicate handlers formerly declared in `GCDOptimizer_Minimap.lua` and `GCDOptimizer_Test.lua` have been removed.

`GCDOptimizer_Test.lua` is excluded from the production TOC. When a developer temporarily loads it, it registers the separate `/gcdopttest` command.

Core loads last and owns bootstrap, configuration, module initialization, segment lifecycle, combat automation, HUD visibility, and command dispatch.

## 7. SavedVariables

The old build erased `GCDOptimizerDB` whenever `NS.VERSION` changed. Version `0.5.0` introduces schema-owned migration:

- compatible fields survive addon updates;
- missing defaults are merged recursively;
- `__addonVersion` records the release;
- `__schemaVersion` determines future migration behavior.

## 8. Removed obsolete API use

The settings panel no longer calls `GetMouseFocus`, which was removed from the modern API. The language menu closes when the panel hides and does not inspect focus state.

## 9. Performance posture

- detector ticker: default `0.05` seconds, active only during a segment;
- HUD ticker: unchanged configurable cadence, stopped while hidden or after segment end;
- cast-success events cause bounded immediate reads, not analytics work;
- input hooks allocate no payload copies;
- failure history is timestamp-only and periodically compacted;
- overlay diagnostics use a bounded ring.

## 10. Required live verification

Static validation cannot prove live event ordering, current hotfixed secrecy policy, or class-specific timing behavior. Before release, test on the target client:

1. fresh login and `/reload` with no Lua errors;
2. all `/gcdopt` commands and minimap gestures;
3. automatic and manual segment lifecycle;
4. an ordinary haste-affected spec and a one-second-GCD spec;
5. off-GCD abilities mixed into the rotation;
6. channelled, empowered, instant, item, and macro actions;
7. combat, encounter, Mythic+, arena, and battleground restriction states;
8. `SPELL_SECRECY_CHANGED` while a segment is active;
9. HUD hidden/shown and long-session timer cleanup;
10. persistence of HUD, language, anchor, and minimap settings across `/reload`.

Record client version, build, Interface, context, Lua errors, and the `/gcdopt debug` output. GitHub issue #1 remains the release gate until this matrix is completed.
