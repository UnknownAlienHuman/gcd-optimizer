# Code index

| Path | Responsibility |
| --- | --- |
| `GCDOptimizer.toc` | Retail 12.1.5 metadata and production load order. |
| `GCDOptimizer_Core.lua` | Composition root, validated config, lifecycle, visibility, sole `/gcdopt` owner. |
| `GCDOptimizer_Util.lua` | Secret-aware GCD/attack-speed boundary, deque, statistics. |
| `GCDOptimizer_GCDEstimator.lua` | Direct/swing calibration, equipment/spec invalidation, source-labeled predictions. |
| `GCDOptimizer_GCDDetector.lua` | Direct starts, activity-gated event fallback, dedupe and estimate upgrade. |
| `GCDOptimizer_PressTracker.lua` | Timestamp-only secure post-hooks. |
| `GCDOptimizer_Integrator.lua` | Piecewise possible-GCD integration; cached data excluded. |
| `GCDOptimizer_Metrics.lua` | Source-aware cadence, exact attribution, latency and SQW recommendation. |
| `GCDOptimizer_Failures.lua` | Payload-free generic player failure timestamps. |
| `GCDOptimizer_Anchors.lua` | Bounded overlay diagnostics. |
| `GCDOptimizer_HUD.lua` | Source-aware mini/details UI and combat-safe SQW control. |
| `GCDOptimizer_Options.lua` | Language settings. |
| `GCDOptimizer_Minimap.lua` | LibDataBroker/LibDBIcon launcher. |
| `GCDOptimizer_Locale.lua` | Localization lookup/tables. |
| `GCDOptimizer_Test.lua` | Optional in-client diagnostics; excluded from the TOC. |
| `tests/test_runtime.lua` | Deterministic Lua source tests; excluded from production. |
| `GCD_RUNTIME_EVIDENCE.md` | Named-build live-client evidence matrix. |
