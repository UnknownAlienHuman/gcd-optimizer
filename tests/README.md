# Tests

From the repository root:

```bash
lua tests/test_runtime.lua
lua tests/test_bootstrap.lua
lua tests/test_continuity.lua
```

The tests stub WoW APIs and verify observation access, source priority, attribution boundaries, exclusion, lifecycle, and deduplication contracts. They do not replace the in-game matrix in `GCD_RUNTIME_EVIDENCE.md`.

The continuity suite exercises blind/policy boundaries, recovery/upgrades, stale callbacks, HUD-independent integration, final-tail checkpoints, bounded history, calibration invalidation, and non-finite configuration. The source suites run under standalone Lua 5.3 and 5.4; these are not client-runtime tests.
