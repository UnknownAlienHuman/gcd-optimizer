# GCD Optimizer

GCD Optimizer is a Retail World of Warcraft HUD for reviewing GCD cadence, queue-window coverage, late input, idle gaps, and server-delay symptoms.

## Current target

- Retail `12.1.5`
- Interface `120105`
- Addon `0.6.0-midnight-12.1.5`
- SavedVariables: `GCDOptimizerDB`

## What changed in 0.6

The timing pipeline is now source-aware:

- `DIRECT_EXACT` — ordinary `C_Spell.GetSpellCooldown(61304)` start/duration/modRate values;
- `ESTIMATED_SWING` — an event timestamp accepted only while the generic GCD activity flag is true, with duration derived from a direct/swing calibration;
- `CACHED_LOW_CONFIDENCE` — display continuity only; it never manufactures a GCD start.

Only exact-to-exact cycles with exactly one eligible local press feed latency and SpellQueueWindow recommendations. Zero candidates are recorded as **unobserved input**; multiple candidates are **ambiguous**. Neither is silently converted into a precise latency sample.

## Installation

Copy the addon directory into:

```text
World of Warcraft/_retail_/Interface/AddOns/GCDOptimizer
```

Restart the client or run `/reload`.

## Controls

- Left-click the minimap icon: show/hide the HUD.
- Right-click the minimap icon: start/stop a manual segment.
- Shift-right-click: reset the segment.
- Right-click the HUD: controls, details, and SpellQueueWindow input.

```text
/gcdopt
/gcdopt show | hide
/gcdopt start | stop | reset
/gcdopt minimap show | hide
/gcdopt debug | anchors | help
```

SpellQueueWindow changes are rejected during combat lockdown.

## Security boundary

`C_Spell.GetSpellCooldown(61304)` and `UnitAttackSpeed("player")` are treated as restriction-sensitive. Values are gated before comparison, branching, arithmetic, formatting, or persistence. `pcall` is used only for error containment, never as a declassification mechanism.

Input hooks retain timestamps only. The addon does not persist action slots, spell names/IDs, macro text, targets, cast GUIDs, combat-log payloads, or raw UI error text.

## Validation status

Deterministic source tests cover:

- direct/modRate normalization;
- inactive versus restricted GCD activity;
- one-second direct calibration and swing fallback;
- exact, ambiguous, and unobserved input attribution;
- exclusion of estimated cycles from exact SQW evidence;
- estimated-to-direct deduplication/upgrade and source-priority protection;
- rejection of off-GCD success events when the generic GCD is inactive or the event is too early for a new cycle;
- suppression of unchanged same-start refreshes and oversized-SQW attribution overlap;
- manual-segment protection when tracking begins inside an already-active GCD.

The named-build in-game matrix remains **NOT-RUN**. Do not treat source tests as proof of live combat behavior; see [`GCD_RUNTIME_EVIDENCE.md`](GCD_RUNTIME_EVIDENCE.md).

## Development map

- [`ARCHITECTURE.md`](ARCHITECTURE.md)
- [`GCD_OBSERVATION_CONTRACT.md`](GCD_OBSERVATION_CONTRACT.md)
- [`README_MIDNIGHT.md`](README_MIDNIGHT.md)
- [`CODE_INDEX.md`](CODE_INDEX.md)
- [`todo.md`](todo.md)
- [WoW addon engineering knowledge base](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb)

Run deterministic tests from the repository root with a standard Lua interpreter:

```bash
lua tests/test_runtime.lua
lua tests/test_bootstrap.lua
```

## License

MIT. Bundled third-party libraries retain their own notices.
