# Agent guide: GCD Optimizer

## Current contract

Target Retail `12.1.0`, Interface `120100`, addon version `0.5.0-midnight-12.1`. Blizzard source baseline: build `12.1.0.69497`, commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`.

Read before changing timing logic:

- `README_MIDNIGHT.md`
- `GCD_RUNTIME_EVIDENCE.md`
- issue #5
- the project knowledge base at `UnknownAlienHuman/wow-addon-engineering-kb`

## Non-negotiable historical fact

The original Midnight implementation contains an intentional `UnitAttackSpeed`-calibrated fallback because direct numerical GCD timing was reported or expected to become Secret in combat. Do **not** remove that fallback based only on a whitelist note, Wowhead flag, out-of-combat read, or another addon's implementation.

The external record also says Blizzard intended `61304` to be non-secret. Treat this as an unresolved runtime discrepancy until a named-build/context matrix exists.

## Runtime map

- `GCDOptimizer_Core.lua`: composition root, DB migration, lifecycle, combat automation, HUD visibility, sole `/gcdopt` dispatcher.
- `GCDOptimizer_GCDEstimator.lua`: direct duration first; attack-speed calibration, EWMA correction, and last-stable fallback.
- `GCDOptimizer_GCDDetector.lua`: direct cooldown polling plus `UNIT_SPELLCAST_SUCCEEDED` candidate-start fallback.
- `GCDOptimizer_PressTracker.lua`: action hooks; local timestamps only enter metrics.
- `GCDOptimizer_Metrics.lua`: queue, late, idle, waste, loss, and SQW analysis.
- `GCDOptimizer_Integrator.lua`: possible-GCD integration from the estimator.
- `GCDOptimizer_Failures.lua`: payload-free failure timestamps.
- `GCDOptimizer_Anchors.lua`: bounded overlay diagnostics.
- `GCDOptimizer_HUD.lua`: presentation; no combat-data discovery.
- `GCDOptimizer_Options.lua` / `GCDOptimizer_Minimap.lua`: settings and launcher adapters.

## Observation classes

Every future hardening pass must distinguish:

- `DIRECT_EXACT`: accessible `61304` numerical start/duration;
- `ESTIMATED_SWING`: duration derived from accessible attack-speed calibration and start inferred from non-secret event/activity evidence;
- `CACHED_LOW_CONFIDENCE`: last stable duration only, with no fabricated exact start.

Do not merge these classes into one undifferentiated metric stream.

## Security invariants

1. Gate every Secret-capable value before branch, comparison, arithmetic, formatting, indexing, logging, persistence, or forwarding.
2. `pcall` is diagnostics/error containment, not declassification.
3. Direct `61304` fields and `UnitAttackSpeed` are independent optional sources; either can become unusable.
4. Never perform swing-ratio arithmetic unless both baseline and current values are ordinary accessible positive numbers.
5. Do not bridge a blind interval as if it were exact evidence.
6. Do not recover spell identity from protected frames, combat log, UI error text, target data, macro text, or timing side channels.
7. Transient spell IDs from `UNIT_SPELLCAST_SUCCEEDED` may only support an explicitly allowed, accessibility-checked classifier and must not be persisted into metrics/SavedVariables.
8. `C_Spell.DoesSpellTriggerGlobalCooldown` is absent from the pinned generated API contract; never assume it exists.

## Correctness invariants

- Direct cooldown starts override event estimates for the same cycle.
- Off-GCD successes must not be counted as exact GCD starts.
- Instant, cast-time, channelled, and empowered event orderings are different test cases.
- One-second base-GCD specs must not inherit a silent `1.5` baseline.
- Weapon swaps and attack-speed-only modifiers must invalidate or recalibrate swing-derived estimates.
- Estimated/ambiguous samples must not drive exact latency or SpellQueueWindow recommendations.
- Detector and HUD tickers must remain segment-scoped and cancellable.

## SavedVariables

Store compatible configuration only. Never persist raw combat samples or protected payloads. Schema changes require explicit migration; release-string changes must not erase user settings.

## Static review

```powershell
rg -n "^## Interface|^## Version" GCDOptimizer.toc
rg -n "SLASH_GCDOPT1|SlashCmdList[.\[]GCDOPT" .
rg -n "UnitAttackSpeed|GetSpellCooldown\(.*61304|UNIT_SPELLCAST_SUCCEEDED" GCDOptimizer_*.lua
rg -n "DoesSpellTriggerGlobalCooldown|COMBAT_LOG_EVENT_UNFILTERED|UI_ERROR_MESSAGE" GCDOptimizer_*.lua
rg -n "GCDOptimizer_Test.lua" GCDOptimizer.toc
```

Expected:

- exactly one production `/gcdopt` dispatcher;
- `UnitAttackSpeed` remains present in the estimator until issue #5 is resolved by runtime evidence;
- all Secret-capable reads have explicit use boundaries;
- no production test harness in the TOC.

## Live verification

Follow `todo.md`, issue #1, and issue #5. Static Lua tests cannot resolve spell-data policy, taint context, or event ordering in the WoW client.
