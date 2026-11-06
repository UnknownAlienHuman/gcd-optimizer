# GCD Optimizer — release checklist

## Source hardening completed

- [x] Target Retail 12.1.5 / Interface `120105`.
- [x] Centralize `61304` and `UnitAttackSpeed` accessibility checks.
- [x] Normalize direct duration by `modRate`.
- [x] Preserve calibration across segment resets.
- [x] Invalidate calibration on equipment/spec changes.
- [x] Calibrate one-second profiles from direct evidence; no class hardcoding.
- [x] Label `DIRECT_EXACT`, `ESTIMATED_SWING`, and `CACHED_LOW_CONFIDENCE`.
- [x] Require confirmed generic-GCD activity for event fallback.
- [x] Remove the nonexistent `C_Spell.DoesSpellTriggerGlobalCooldown` path.
- [x] Upgrade a nearby estimate when later direct timing arrives.
- [x] Prevent lower-quality same-cycle data from overwriting exact timing.
- [x] Suppress unchanged exact-poll refresh spam.
- [x] Treat zero press candidates as unobserved and multiple as ambiguous.
- [x] Exclude estimated, unobserved, and ambiguous samples from exact latency/SQW evidence.
- [x] Stop using missing press hooks as proof of AFK.
- [x] Prevent oversized SQW attribution from reaching the previous GCD-start press.
- [x] Guard SpellQueueWindow changes during combat lockdown.
- [x] Cancel detector/HUD timers before replacement and teardown.
- [x] Add deterministic tests for secrecy states, one-second calibration, attribution, off-GCD rejection, transitions, and dedupe.

## Static/source gate

- [x] Lua syntax check for modified production/test files.
- [x] `lua tests/test_runtime.lua`.
- [x] `lua tests/test_bootstrap.lua`.
- [x] One production `/gcdopt` owner.
- [x] Developer harness excluded from the TOC.
- [x] No combat-log/raw UI-error failure inference.

## Current-client release gate — NOT-RUN

Record exact version/build/Interface/date/spec/content/restriction/taint state.

- [ ] Outside combat probe.
- [ ] Open-world combat probe.
- [ ] Encounter and Mythic+ probe.
- [ ] Arena and battleground probe.
- [ ] `SPELL_SECRECY_CHANGED` transition.
- [ ] Ordinary and one-second profiles.
- [ ] Weapon swaps, haste changes, and attack-speed-only effects.
- [ ] Instant, cast-time, channelled, empowered, item, macro, and mixed off-GCD actions.
- [ ] Manual timeline comparison for exact/estimated starts.
- [ ] Login, `/reload`, controls, minimap, persistence, ticker cleanup, Lua/taint errors.

Issues #1 and #5 remain live-client gates. Do not package a public release until this matrix is recorded.
