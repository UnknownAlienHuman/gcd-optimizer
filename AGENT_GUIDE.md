# Agent guide

## Target

- Retail `12.1.5`
- Interface `120105`
- Addon `0.6.0-midnight-12.1.5`
- Production slash-command owner: `GCDOptimizer_Core.lua`
- Production load order: `GCDOptimizer.toc`

Before changing timing/security behavior, read:

1. `GCD_OBSERVATION_CONTRACT.md`
2. `GCD_RUNTIME_EVIDENCE.md`
3. the current `wow-addon-engineering-kb` routes for spell secrecy, patch migration, lifecycle, persistence, and performance.

## Non-negotiable invariants

1. Gate every restriction-sensitive return before comparison, branching, arithmetic, formatting, indexing, or persistence.
2. `pcall` contains errors; it never makes Secret data ordinary.
3. Do not add `C_Spell.DoesSpellTriggerGlobalCooldown`; it is absent from the selected generated API.
4. `UNIT_SPELLCAST_SUCCEEDED` is a wake/candidate signal. An estimated start requires confirmed generic-GCD activity.
5. Every accepted start carries one source: `DIRECT_EXACT` or `ESTIMATED_SWING`. Cached values never create starts, and source quality never decreases within a deduplicated cycle.
6. Exact latency/SQW evidence requires an exact-to-exact cycle and exactly one eligible local press.
7. Zero input candidates mean `unobserved_input`, not AFK. Multiple candidates mean `ambiguous_multi_press`; attribution never reaches back to the press that started the previous GCD.
8. Weapon/spec changes invalidate swing calibration without erasing the last stable display duration.
9. Tickers/timers have one owner, are bounded, and are cancelled before replacement and on teardown.
10. Runtime behavior is not proven until the named-build matrix is run in game.

## Verification

Minimum source gate:

```bash
lua tests/test_runtime.lua
lua tests/test_bootstrap.lua
```

Also verify:

- no production duplicate `/gcdopt` owner;
- test harness excluded from the TOC;
- no raw combat-log/UI-error reason inference;
- `Interface` and version metadata match the selected patch;
- all modified Lua parses;
- branch diff is reviewed before merge.

Report source-test results separately from live-client results.
