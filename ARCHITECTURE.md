# Architecture

The TOC loads shared utilities and locale data before the estimator and core bootstrap, then trackers, metrics, detector, failure observer, HUD/options/minimap UI, and test helpers.

`GCDOptimizer_Core.lua` owns initialization, the saved-variable configuration, and top-level lifecycle events. Press tracking, GCD detection, and estimation feed `GCDOptimizer_Metrics.lua`; failures provide a separate event-derived diagnostic channel. `GCDOptimizer_HUD.lua` renders the presentation while anchors, options, and minimap files provide user interaction.

State is persisted in `GCDOptimizerDB`; transient timing samples, trackers, and UI frame state are module-local. Test HUD visibility, lifecycle reinitialization, combat timing, and reset/start/stop controls in-game before publishing.
