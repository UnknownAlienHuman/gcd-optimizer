# GCD Optimizer

GCD Optimizer is a World of Warcraft HUD for reviewing global-cooldown cadence, queue-window coverage, late input, idle gaps, and server-delay symptoms.

## Current source state

- Game target: Retail 12.1.0
- Interface: `120100`
- Addon version: `0.5.0-midnight-12.1`
- Author: Neomorph
- Saved variables: `GCDOptimizerDB`
- Blizzard UI baseline: `12.1.0.69497`, `Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`

The repository is **not yet a packaged release candidate**. Current-client verification is tracked by issues #1 and #5.

## Installation

Copy the `GCDOptimizer` directory into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Restart the client or run `/reload`. Bundled libraries live under `libs/`.

## Controls

- Left-click the minimap icon: show or hide the HUD.
- Right-click the minimap icon: start or stop a manual segment.
- Shift-right-click the minimap icon: reset the current segment while preserving its running state.
- Right-click the HUD: open its runtime menu.

```text
/gcdopt
/gcdopt show | hide
/gcdopt start | stop | reset
/gcdopt minimap show | hide
/gcdopt debug | anchors | help
```

## GCD observation model

The addon must support more than one evidence mode.

### Exact mode

When ordinary numeric fields from `C_Spell.GetSpellCooldown(61304)` are readable, the detector uses the reported cooldown start and duration and deduplicates starts by time.

### Estimated combat fallback

The original Midnight implementation exists because the numerical `61304` cooldown was observed or expected to become Secret in combat. When the direct duration cannot be used, the estimator falls back to:

1. an out-of-combat `UnitAttackSpeed("player")` baseline;
2. the `baseSwing / currentSwing` ratio as a haste proxy;
3. cast-to-cast EWMA as a conservative correction;
4. the last stable estimate.

`UNIT_SPELLCAST_SUCCEEDED` supplies a non-Secret local timestamp for the legacy fallback detector. This path is estimated, not equivalent to an authoritative cooldown start.

### Unresolved evidence conflict

Blizzard-origin notes and WoWUIDev discussions describe spell `61304` as intentionally whitelisted/non-secret. The project history says the numerical cooldown still became Secret in combat and motivated the swing-speed redesign. The exact build, restriction state, and taint context of that observation have not yet been recovered.

Therefore:

- the direct source remains preferred whenever accessible;
- the attack-speed fallback must not be removed solely because a whitelist was documented;
- direct and estimated samples must eventually be labeled separately;
- current-build combat, encounter, Mythic+, arena, and battleground probes remain mandatory.

## Known limitations of the restored fallback

- `UnitAttackSpeed` is itself restriction-sensitive and must be rejected when inaccessible.
- Weapon changes and attack-speed modifiers may not represent spell GCD haste exactly.
- One-second base-GCD specs require correct baseline calibration.
- `UNIT_SPELLCAST_SUCCEEDED` can fire for off-GCD actions and at different points for instant, cast-time, and channelled spells.
- Current metrics do not yet separate exact, estimated, and ambiguous samples.

The restored code prevents the direct-only regression, but these points remain release blockers rather than being hidden behind confident labels.

## Other security boundaries

Input hooks retain local timestamps only. Metrics do not persist action slots, macro text, spell names, targets, cast GUIDs, or protected payloads. Failure diagnostics avoid combat-log and raw UI-error inference.

## Saved-variable upgrades

Compatible settings are merged into `GCDOptimizerDB`. Release strings no longer erase the user's configuration; incompatible changes require an explicit schema migration.

## Development

- [Retail 12.1 engineering notes](README_MIDNIGHT.md)
- [Runtime evidence contract](GCD_RUNTIME_EVIDENCE.md)
- [Architecture](ARCHITECTURE.md)
- [Code index](CODE_INDEX.md)
- [Code graph](CODE_GRAPH.md)
- [Changelog](CHANGELOG.md)
- [Release checklist](todo.md)
- [WoW addon engineering knowledge base](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb)

## License

Licensed under the [MIT License](LICENSE). Bundled third-party components remain under their own notices.
