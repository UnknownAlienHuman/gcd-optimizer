# Code index

| Path | Responsibility |
| --- | --- |
| `GCDOptimizer.toc` | Retail 12.1 metadata, libraries, runtime load order; excludes developer harnesses. |
| `GCDOptimizer_Core.lua` | Composition root, DB migration, lifecycle, combat automation, HUD visibility, sole `/gcdopt` dispatcher. |
| `GCDOptimizer_Util.lua` | Shared helpers, deque, statistics, and newer accessibility helpers used by supporting modules. |
| `GCDOptimizer_GCDEstimator.lua` | Direct GCD duration, attack-speed calibration, EWMA correction, and last-stable fallback. |
| `GCDOptimizer_GCDDetector.lua` | Direct `61304` polling plus event-derived candidate starts when direct timing is unavailable. |
| `GCDOptimizer_PressTracker.lua` | Secure post-hooks; local press timestamps only. |
| `GCDOptimizer_Integrator.lua` | Piecewise possible-GCD integration from the estimator. |
| `GCDOptimizer_Metrics.lua` | Queue/late/idle/loss/SQW accounting; source-confidence separation remains open. |
| `GCDOptimizer_Failures.lua` | Payload-free player cast-failure timestamps and generic summaries. |
| `GCDOptimizer_Anchors.lua` | Bounded overlay glow diagnostics. |
| `GCDOptimizer_HUD.lua` | Rendering and recommendations. |
| `GCDOptimizer_Options.lua` | Language settings panel. |
| `GCDOptimizer_Minimap.lua` | LibDataBroker/LibDBIcon launcher. |
| `GCDOptimizer_Locale.lua` | Localization tables and lookup helpers. |
| `GCDOptimizer_Test.lua` | Developer-only diagnostics; not loaded in production. |
| `GCD_RUNTIME_EVIDENCE.md` | Conflicting evidence, probe contract, and acceptance criteria. |
| `README_MIDNIGHT.md` | Retail 12.1 implementation notes and known debt. |
| `todo.md` | Release-gate checklist. |
