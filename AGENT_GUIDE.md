# Agent guide: GCDOptimizer

## Start here

[`GCDOptimizer.toc`](GCDOptimizer.toc) is the load-order contract: vendored LibStub/CallbackHandler/LibDataBroker/LibDBIcon, utility/locale, estimator, core, press/integration, metrics, detector, anchors/failures, then HUD/options/minimap/test. `GCDOptimizer_Core.lua:NS:Init` is the bootstrap; its event frame handles `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_REGEN_DISABLED`, and `PLAYER_REGEN_ENABLED`.

## Runtime map

- `GCDOptimizer_Core.lua:NS:GetConfig` owns `GCDOptimizerDB`, defaults, and version reset. `NS.state` owns segment lifecycle (`inSegment`, start/end, effective end, auto-combat); all submodules are called through `SafeCall` in `NS:StartSegment`, `PauseSegment`, `ResetSegment`, and `ResetAndContinue`.
- `GCDOptimizer_PressTracker.lua` installs input/action/cast hooks and sends normalized presses to `NS.Metrics:OnPress` only while a segment is active.
- `GCDOptimizer_GCDDetector.lua` observes player successful casts and samples the GCD spell (`61304`) with a ticker; `GCDOptimizer_GCDEstimator.lua` combines observations and cast successes into predicted/observed GCD values.
- `GCDOptimizer_Integrator.lua` samples predicted GCD/possible fight windows; `GCDOptimizer_Metrics.lua` owns timing aggregates (queue lead, late press, waste, AFK, lost GCD, APM, gaps).
- `GCDOptimizer_Anchors.lua` correlates activation overlays and spellcast sent/succeeded/failed/interrupted events; `GCDOptimizer_Failures.lua` records `UI_ERROR_MESSAGE`, player cast failures, and optional combat-log diagnostics.
- `GCDOptimizer_HUD.lua` renders the current/final metric snapshot and runs a ticker while visible. Options and minimap are UI/config adapters. The `/gcdopt` handler is assigned in `GCDOptimizer_Core.lua:349-390`, reassigned by `GCDOptimizer_Minimap.lua:105-135`, and reassigned a third time by the last-loaded `GCDOptimizer_Test.lua:108-120`; the final handler currently exposes only `test`, `debug`, and `anchors`, so the production `start`/`stop`/`reset`/`show`/`hide` commands are shadowed until load order or registration is fixed. Track the unification in [GitHub issue #2](https://github.com/UnknownAlienHuman/gcd-optimizer/issues/2).

## State and dependencies

`GCDOptimizerDB` stores configuration, HUD visibility/position, anchors, and minimap settings. Timing samples, segment counters, recent cast/overlay rings, detector state, and failure windows are transient module tables. `LibStub`, `CallbackHandler-1.0`, `LibDataBroker-1.1`, and `LibDBIcon-1.0` are vendored; TOC marks them `OptionalDeps` for compatibility with already-loaded copies. `libs/LibDBIcon-1.0/lib.xml` is present but inactive because the root TOC loads the library Lua file directly. No in-house addon is required.

## Change routing

- Change configuration/version migration: `GCDOptimizer_Core.lua:DEFAULTS` and `NS:GetConfig`; update `GCDOptimizer_Options.lua` only for controls.
- Change segment start/stop/reset or combat auto mode: `GCDOptimizer_Core.lua:NS:StartSegment`, `PauseSegment`, `ResetSegment`, `OnCombatStart`, `OnCombatEnd`.
- Change press classification or source hooks: `GCDOptimizer_PressTracker.lua` and `GCDOptimizer_Integrator.lua`; keep `NS.Metrics:OnPress` as the single metric ingress.
- Change GCD observations/prediction: `GCDOptimizer_GCDDetector.lua` and `GCDOptimizer_GCDEstimator.lua`; do not recompute in HUD.
- Change accounting formulas: `GCDOptimizer_Metrics.lua`; update HUD labels/tests with any field-name change.
- Change failure taxonomy: `GCDOptimizer_Failures.lua`; keep failure diagnostics separate from timing aggregates.
- Change presentation/refresh cadence: `GCDOptimizer_HUD.lua`; keep ticker stopped when hidden or segment-ended.
- Change placement or minimap: `GCDOptimizer_Anchors.lua`/`GCDOptimizer_Minimap.lua`; preserve DB anchor schema.

## Invariants/risks

- `NS.state.inSegment` gates all timing writes; starting twice must not duplicate resets, and ending must set `segmentEndEffective` consistently.
- Timing is sensitive to event ordering and clock resolution. Preserve monotonic timestamps, the detector's minimum delta/drift thresholds, and anchor ring bounds.
- `COMBAT_LOG_EVENT_UNFILTERED`, cast/GCD APIs, and activation overlays may be restricted or secret in Midnight. `Failures` and `Anchors` must fail closed without arithmetic on unreadable values.
- HUD ticker and detector/metrics tickers are hot paths. Avoid per-tick allocations and stop timers on segment end; no protected action is performed by this addon.
- SavedVariables version reset is intentional (`__addonVersion`); do not silently change the schema without migration/reset policy.

## Verification

Static checks:

```powershell
Get-Content _Addons/GCDOptimizer/GCDOptimizer.toc
rg -n "GCDOptimizerDB|NS:StartSegment|Metrics:OnPress|GCDDetector|GCDEstimator|SlashCmdList|COMBAT_LOG" _Addons/GCDOptimizer
```

In-game: first verify the current final slash surface with `/gcdopt test`, `/gcdopt debug`, and `/gcdopt anchors`; the production handler in `Core.lua`/`Minimap.lua` is currently shadowed by `GCDOptimizer_Test.lua`. Then test the underlying segment lifecycle through its UI/controlled calls (`start`, `stop`, `reset`, `show`, `hide`), auto combat start/stop, normal/queued/late presses, spell queue window changes, cast failures, reload persistence, HUD drag/anchors, and restricted-value builds. Compare HUD totals with the debug/test panel and inspect client errors after a long combat segment.

## Unknowns

Static review cannot prove the accuracy of timing against the current server queue window or every class/build's GCD behavior. Treat measured calibration and target-client event availability as live-test evidence, not code-truth assumptions.
