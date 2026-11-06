# Tests

From the repository root:

```bash
lua tests/test_runtime.lua
lua tests/test_bootstrap.lua
```

The tests stub WoW APIs and verify observation access, source priority, attribution boundaries, exclusion, lifecycle, and deduplication contracts. They do not replace the in-game matrix in `GCD_RUNTIME_EVIDENCE.md`.
