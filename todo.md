# GCD Optimizer — release checklist

## Completed static migration

- [x] Target Retail 12.1.0 with exact Interface `120100`.
- [x] Bump addon/Core/docs to `0.5.0-midnight-12.1`.
- [x] Centralize and gate all `C_Spell.GetSpellCooldown(61304)` fields before use.
- [x] Remove `DoesSpellTriggerGlobalCooldown` dependency and cast-success GCD inference.
- [x] Initialize `GCDOptimizer_GCDDetector` from Core.
- [x] Reduce detector polling from 50 Hz to 20 Hz by default and stop it outside segments.
- [x] Remove swing-speed/haste reconstruction.
- [x] Make press tracking timestamp-only.
- [x] Remove combat-log and `UI_ERROR_MESSAGE` failure inference.
- [x] Gate overlay spell IDs and bound diagnostic history.
- [x] Replace obsolete `GetMouseFocus` logic.
- [x] Make Core the only `/gcdopt` owner.
- [x] Exclude `GCDOptimizer_Test.lua` from the production TOC and move it to `/gcdopttest`.
- [x] Preserve compatible SavedVariables through schema-owned migration.
- [x] Run syntax and forbidden-symbol checks for every changed runtime Lua file.

## Required in-game release gate

Record exact client version, build, Interface, date, and restriction context for every result.

- [ ] Fresh login and `/reload`: no Lua errors, taint errors, forbidden-object errors, or repeating callbacks.
- [ ] Verify `/gcdopt`, `show`, `hide`, `start`, `stop`, `reset`, `minimap show/hide`, `debug`, `anchors`, and `help`.
- [ ] Verify minimap left-click, right-click, and shift-right-click behavior.
- [ ] Verify auto combat start/stop and replacement of a running manual segment.
- [ ] Verify reset preserves running/auto state and settings survive `/reload`.
- [ ] Test an ordinary haste-scaled GCD spec and a one-second-GCD spec.
- [ ] Mix off-GCD abilities into the rotation and confirm they never add GCD starts.
- [ ] Test instant, cast-time, channelled, empowered, macro, spellbook, item, and action-bar use paths.
- [ ] Change `SpellQueueWindow` and verify queue/late classifications and recommendation stability.
- [ ] Test combat, encounter, Mythic+, arena, and battleground restriction states.
- [ ] Trigger or observe `SPELL_SECRECY_CHANGED` during a segment.
- [ ] Confirm inaccessible `61304` data fails closed without Lua errors or fabricated timing.
- [ ] Hide/show the HUD repeatedly and run a long segment to confirm ticker cleanup and stable CPU/GC behavior.
- [ ] Compare HUD totals with a recorded manual timeline and `/gcdopt debug` output.

This matrix remains tracked by GitHub issue #1 and must be completed before packaging the release.
