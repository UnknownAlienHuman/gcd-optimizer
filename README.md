# GCD Optimizer

GCD Optimizer is a lightweight World of Warcraft HUD for reviewing global-cooldown cadence, queue-window coverage, late input, idle gaps, and server-delay symptoms.

![GCD Optimizer timing HUD](https://media.forgecdn.net/attachments/1510/156/screenshot-2026-02-02-054015-png.png)

Screenshot from the [CurseForge gallery](https://www.curseforge.com/wow/addons/gcd-optimizer).

## Current release

- Game: Retail 12.1.0
- Interface: `120100`
- Addon version: `0.5.0-midnight-12.1`
- Author: Neomorph
- Saved variables: `GCDOptimizerDB`
- Engineering baseline: Blizzard UI source `12.1.0.69497`, commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`, reviewed 2026-08-27

## Installation

Copy the `GCDOptimizer` directory into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Restart the client or run `/reload`. LibStub, CallbackHandler, LibDataBroker, and LibDBIcon are bundled under `libs/`.

## Controls

- Left-click the minimap icon: show or hide the HUD.
- Right-click the minimap icon: start or stop a manual segment.
- Shift-right-click the minimap icon: reset the current segment while preserving its running state.
- Right-click the HUD: open its runtime menu.

The single slash-command dispatcher supports:

```text
/gcdopt
/gcdopt show
/gcdopt hide
/gcdopt start
/gcdopt stop
/gcdopt reset
/gcdopt minimap show
/gcdopt minimap hide
/gcdopt debug
/gcdopt anchors
/gcdopt help
```

## Retail 12.1 data model

The addon reads the GCD dummy spell (`61304`) only through a centralized accessibility gate. A successful player cast requests an immediate cooldown read but is not itself counted as a new GCD; this prevents off-GCD abilities from inflating the sample.

Input hooks discard all arguments and retain only ordinary local timestamps. The addon does not persist spell IDs, spell names, macro text, targets, cast GUIDs, or other protected input payloads in metrics state.

When the GCD cooldown is inaccessible, timing detection fails closed and the HUD retains only the last ordinary duration observed in the current session. No alternate combat API is used to reconstruct hidden state.

Failure diagnostics count player cast failures without parsing `UI_ERROR_MESSAGE`, combat-log data, targets, resources, or restricted text. In 12.1 the displayed reason is therefore intentionally generic unless Blizzard exposes a safe source in a future contract.

## Saved-variable upgrades

Version updates now merge compatible defaults into `GCDOptimizerDB` instead of erasing user settings whenever the release string changes. Destructive changes, if ever required, are owned by an explicit schema migration.

## Development and verification

- [Architecture](ARCHITECTURE.md)
- [Code index](CODE_INDEX.md)
- [Code graph](CODE_GRAPH.md)
- [Retail 12.1 implementation notes](README_MIDNIGHT.md)
- [Changelog](CHANGELOG.md)
- [Release checklist](todo.md)
- [WoW addon engineering knowledge base](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb)

Static source validation is part of this repository update. A current-client combat smoke test remains mandatory before publishing a packaged release; it is tracked in GitHub issue #1.

## Published addon

[CurseForge: GCD Optimizer](https://www.curseforge.com/wow/addons/gcd-optimizer)

## License

Licensed under the [MIT License](LICENSE). Bundled third-party components remain under their own notices.
