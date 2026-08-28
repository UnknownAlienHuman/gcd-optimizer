# Agent guide: GCD Optimizer

## Current contract

Target Retail `12.1.0`, Interface `120100`, addon version `0.5.0-midnight-12.1`. The pinned engineering baseline is Blizzard build `12.1.0.69497`, source commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`, reviewed 2026-08-27.

Read the project knowledge base before changing code:

- [wow-addon-engineering-kb](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb)
- `KB/addon/Patch_12_1_0_Addon_Changes.md`
- `KB/core/BlizzardUI_security.md`
- `KB/core/BlizzardUI_Performance_Modules.md`
- `KB/deep/Spell_Secrecy_Registry_12_1_0.md`

## Load order and bootstrap

`GCDOptimizer.toc` loads libraries, utilities/locales, runtime modules, UI adapters, and finally `GCDOptimizer_Core.lua`. Core owns:

- SavedVariables/default migration;
- module initialization;
- segment start, pause, reset, and combat automation;
- HUD visibility;
- the only `/gcdopt` registration.

`GCDOptimizer_Test.lua` is intentionally absent from the production TOC and uses `/gcdopttest` when manually enabled.

## Runtime map

- `GCDOptimizer_Util.lua`: accessibility predicates, the centralized `C_Spell.GetSpellCooldown` boundary, deque, and statistics.
- `GCDOptimizer_GCDEstimator.lua`: last accessible GCD duration and session fallback; no unit-stat or swing-speed inference.
- `GCDOptimizer_GCDDetector.lua`: segment-only polling of spell `61304`; cast success schedules a read but never proves a GCD.
- `GCDOptimizer_PressTracker.lua`: secure hooks with zero-argument callbacks; only local timestamps enter metrics.
- `GCDOptimizer_Metrics.lua`: queue, late, idle, waste, lost-GCD, and SQW analysis.
- `GCDOptimizer_Integrator.lua`: piecewise predicted-GCD integration.
- `GCDOptimizer_Failures.lua`: payload-free player cast-failure timestamps; public reason is generic `OTH`.
- `GCDOptimizer_Anchors.lua`: bounded, optional overlay show/hide diagnostics with accessibility-gated spell IDs.
- `GCDOptimizer_HUD.lua`: rendering and analysis; do not move combat-data reads into the HUD.
- `GCDOptimizer_Options.lua`: language panel only.
- `GCDOptimizer_Minimap.lua`: LDB/DBIcon adapter; no slash registration.

## Security invariants

1. Gate Secret-capable values before branch, comparison, arithmetic, formatting, concatenation, indexing, iteration, logging, persistence, or forwarding.
2. `issecretvalue` describes provenance; use `canaccessvalue`/`canaccessallvalues` for the use boundary.
3. `pcall` is not declassification.
4. Do not add combat-log, raw aura, UI-error-text, focus/layout, or forbidden-object inference paths.
5. Do not retain action, spell, macro, item, target, cast-GUID, or error payloads merely because one build currently exposes them.
6. Do not replace Blizzard globals or monkey-patch secure APIs.
7. If `61304` becomes inaccessible, fail closed. Do not reconstruct the hidden duration from another restricted statistic.

## Lifecycle invariants

- `NS.state.inSegment` gates all timing writes.
- Detector/HUD tickers must be cancelled on reset/end and must not multiply after `/reload` or repeated starts.
- `GCDDetector:Init()` must run before `OnSegmentStart()`.
- Metrics and Integrator must start before Detector's first poll can emit `NS:OnGCDStart`.
- A pre-existing cooldown is primed but not counted for manual starts; the first auto-combat GCD may reanchor Metrics and Integrator by at most two seconds.
- Entering combat replaces a running manual segment only when combat autostart is enabled.
- Auto-stop applies only to an auto-started combat segment.
- Reset preserves the current running/auto state through `ResetAndContinue`.

## SavedVariables

`GCDOptimizerDB` is migrated by `__schemaVersion`, not erased on every release string change. Additive defaults belong in `GCDOptimizer_Core.lua:DEFAULTS`. Any incompatible schema change requires an explicit, reviewable migration.

Never store transient timing samples or restricted payloads in SavedVariables.

## Change routing

- API/accessibility boundary: `GCDOptimizer_Util.lua`.
- GCD source or de-duplication: `GCDOptimizer_GCDDetector.lua` and `GCDOptimizer_GCDEstimator.lua`.
- Input sources: `GCDOptimizer_PressTracker.lua`; callbacks must remain payload-free.
- Accounting formulas: `GCDOptimizer_Metrics.lua`; update labels and test evidence together.
- Segment/combat behavior or commands: `GCDOptimizer_Core.lua`.
- Failure evidence: `GCDOptimizer_Failures.lua`; do not recover removed reason inference without a current contract.
- Presentation: `GCDOptimizer_HUD.lua`; keep data collection outside render code.
- Launcher/settings: `GCDOptimizer_Minimap.lua` and `GCDOptimizer_Options.lua`.

## Static verification

```powershell
rg -n "^## Interface|^## Version" GCDOptimizer.toc
rg -n "SLASH_GCDOPT1|SlashCmdList[.\[]GCDOPT" .
rg -n "DoesSpellTriggerGlobalCooldown|GetMouseFocus|COMBAT_LOG_EVENT_UNFILTERED|UI_ERROR_MESSAGE" .
rg -n "UnitAttackSpeed|UnitSpellHaste|RunMacroText" GCDOptimizer_*.lua
rg -n "GCDOptimizer_Test.lua" GCDOptimizer.toc
```

Expected results:

- Interface `120100` and version `0.5.0-midnight-12.1`;
- exactly one production `/gcdopt` registration, in Core;
- no obsolete API or restricted inference matches in runtime files;
- no test harness in the TOC.

## Live verification

Follow [todo.md](todo.md) and GitHub issue #1. Static review cannot establish current hotfixed secrecy policy, real client event ordering, or class-specific accuracy. Record build/context and preserve failures as evidence rather than guessing.
