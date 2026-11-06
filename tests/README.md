# Tests

From the repository root:

```bash
lua tests/test_runtime.lua
lua tests/test_bootstrap.lua
lua tests/test_continuity.lua
lua tests/test_review.lua
lua tests/test_ingress.lua
```

The tests stub WoW APIs and verify observation access, source priority, attribution boundaries, exclusion, lifecycle, and deduplication contracts. They do not replace the in-game matrix in `GCD_RUNTIME_EVIDENCE.md`.

The continuity suite exercises blind/policy boundaries, recovery/upgrades, stale callbacks, HUD-independent integration, final-tail checkpoints, bounded history, calibration invalidation, and non-finite configuration. The source suites run under standalone Lua 5.3 and 5.4; these are not client-runtime tests.

The review suite runs real detector, estimator, integrator, metrics, HUD and Core modules against an explicit UI mock (unknown methods stay nil). It checks sample aging, late-only evidence, upper-bound SQW search against 120 exhaustive-reference datasets, rolling/segment denominators, long segments, blind recovery, duration drift, stale UI actions/tickers, and combat-safe CVar application. Localization, libraries and the full client widget/event implementation are outside this mock's scope.

The ingress suite covers input-history eviction and recovery (including 120 bounded-burst reference sequences), idle calibration, restricted first combat, reload readiness, malformed minimap settings, and fresh system-delay evidence.
