# Code index

| Path | Responsibility |
| --- | --- |
| `GCDOptimizer.toc` | Retail 12.1 metadata, libraries, runtime load order; excludes the developer harness. |
| `GCDOptimizer_Core.lua` | Composition root, DB schema/default migration, lifecycle, combat automation, HUD visibility, sole `/gcdopt` dispatcher. |
| `GCDOptimizer_Util.lua` | Secret accessibility gate, spell/GCD cooldown read boundary, deque, statistics. |
| `GCDOptimizer_GCDEstimator.lua` | Last accessible GCD duration and session fallback. |
| `GCDOptimizer_GCDDetector.lua` | Real `61304` cooldown-start detection and de-duplication. |
| `GCDOptimizer_PressTracker.lua` | Payload-free secure hooks; local press timestamps only. |
| `GCDOptimizer_Integrator.lua` | Piecewise possible-GCD integration. |
| `GCDOptimizer_Metrics.lua` | Queue/late/idle/loss/SQW accounting and rolling contexts. |
| `GCDOptimizer_Failures.lua` | Payload-free player cast-failure timestamps and generic summaries. |
| `GCDOptimizer_Anchors.lua` | Accessibility-gated overlay glow diagnostics in a bounded ring. |
| `GCDOptimizer_HUD.lua` | Mini/details rendering, recommendations, and runtime menu. |
| `GCDOptimizer_Options.lua` | Language settings panel; no obsolete focus API. |
| `GCDOptimizer_Minimap.lua` | LibDataBroker/LibDBIcon launcher; no slash-command ownership. |
| `GCDOptimizer_Locale.lua` | Localization tables and lookup helpers. |
| `GCDOptimizer_Test.lua` | Developer-only `/gcdopttest` diagnostics, not loaded in production. |
| `README_MIDNIGHT.md` | Retail 12.1 implementation and live-test contract. |
| `todo.md` | Release-gate smoke matrix. |
