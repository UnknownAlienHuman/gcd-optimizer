# GCD Optimizer — Retail 12.1 engineering notes

## Baseline

| Field | Value |
| --- | --- |
| Addon version | `0.5.0-midnight-12.1` |
| Patch contract | Retail `12.1.0` |
| Interface | `120100` |
| Blizzard source build | `12.1.0.69497` |
| Blizzard source commit | `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4` |
| Review date | 2026-08-29 |

## 1. Correction to the direct-only migration

The first 12.1 pass removed `UnitAttackSpeed` estimation and treated accessible `C_Spell.GetSpellCooldown(61304)` values as the only valid GCD source. That change was not justified by the addon's runtime history.

The pre-update source explicitly documents that the numerical GCD cooldown could become Secret in Midnight combat. Its attack-speed path was an intentional degradation model, not unused legacy code. The known estimator and detector were restored in commit `d46f268e90ea9b669ff8570a61954b8ff21dd97f` while retaining unrelated 12.1 fixes such as Core initialization, command ownership, SavedVariables migration, payload-free input tracking, and generic failure handling.

## 2. Evidence conflict

Two evidence sets currently disagree:

### Documented/community evidence

Blizzard-origin addon-engineering notes list `61304` among cooldowns flagged non-secret. WoWUIDev discussions in January, February, and May 2026 describe direct reads of the GCD dummy spell as usable, including in combat-oriented UI code.

### Project evidence

The original GCD Optimizer implementation says direct numeric cooldown timing became Secret in Midnight combat and therefore uses attack-speed calibration plus local cast timestamps.

The original upstream monorepo commit date and the exact client build/error log behind that decision are not available in the split repository. Until a named-build runtime matrix resolves the discrepancy, neither evidence set is allowed to erase the other.

## 3. Current source priority

### 3.1 Direct exact timing

When `startTime` and `duration` from spell `61304` are ordinary usable numbers, they are the highest-quality source. The detector polls the cooldown and deduplicates starts with a drift epsilon and minimum-start interval.

The current generated API still marks `C_Spell.GetSpellCooldown` as restriction-sensitive. `SpellCooldownInfo.isActive`, `isEnabled`, and `isOnGCD` have stronger field contracts, but `isOnGCD` is documented as trustworthy only while responding to `SPELL_UPDATE_COOLDOWN`.

### 3.2 Attack-speed duration estimate

When direct GCD duration cannot be used, the restored estimator:

1. records an out-of-combat main-hand swing-speed baseline;
2. reads the current main-hand speed when accessible;
3. estimates a haste multiplier as `baseSwing / currentSwing`;
4. computes `baseGCD / hasteMultiplier`;
5. clamps the result to `[0.75, 1.5]`;
6. may gently lower the estimate using cast-to-cast EWMA;
7. otherwise retains the last stable estimate.

This preserves functionality under the project's reported combat behavior, but it is an approximation. Attack speed can diverge from spell haste/GCD behavior through weapon changes, class rules, attack-speed-only effects, or an incorrect base-GCD calibration.

`UnitAttackSpeed` is also tagged as restriction-sensitive in current generated docs. It must be treated as an optional source and never used in arithmetic when Secret or inaccessible.

### 3.3 Event-derived start estimate

When direct cooldown starts are unavailable, `UNIT_SPELLCAST_SUCCEEDED` supplies a local event timestamp. The restored detector treats eligible player success events as candidate starts and applies a minimum interval to suppress duplicates.

Known defects:

- the current generated API does not expose `C_Spell.DoesSpellTriggerGlobalCooldown`;
- the conservative fallback can count off-GCD successes;
- cast-time success occurs at a different point from an instant spell's GCD start;
- channel and empowered event ordering require separate validation;
- a local success timestamp is an estimate, not the server's authoritative GCD start.

This path must not be presented as exact latency evidence.

## 4. Required final architecture

The stable target is a confidence-aware hybrid:

```text
DIRECT_EXACT
  accessible 61304 start/duration
  -> exact start + observed duration

ESTIMATED_SWING
  direct numeric GCD unavailable
  + accessible attack speed calibration
  + event/cooldown activity evidence
  -> estimated start/duration

CACHED_LOW_CONFIDENCE
  neither direct timing nor swing speed usable
  -> preserve last stable duration only
  -> do not manufacture exact samples
```

Metrics must record the observation source. Exact latency and SpellQueueWindow recommendations must exclude low-confidence and ambiguous samples until their error model is validated.

## 5. Input and failure boundaries retained from the 12.1 pass

`GCDOptimizer_PressTracker.lua` keeps only local timestamps from secure post-hooks. It does not persist action slots, spell IDs, macro text, item IDs, targets, or cast GUIDs.

`GCDOptimizer_Failures.lua` records payload-free player failure timestamps. It does not reconstruct restricted reasons through combat log or UI error text.

These changes are independent of the GCD source regression and remain in place.

## 6. Lifecycle

Core owns bootstrap, configuration, segment lifecycle, combat automation, HUD visibility, and `/gcdopt`. `GCDDetector:Init()` is called before tracking begins. Detector and HUD tickers are cancelled outside active use.

The restored detector currently counts the first observed active GCD in a segment. Manual versus auto-combat priming/reanchoring needs live regression testing because the restored event fallback predates the newer lifecycle assumptions.

## 7. Required runtime matrix

Record exact client version, build, Interface, date, content type, and taint/restriction context.

For spell `61304`, capture:

```text
C_Secrets.HasSecretRestrictions()
C_Secrets.ShouldCooldownsBeSecret()
C_Secrets.GetSpellCooldownSecrecy(61304)
C_Secrets.ShouldSpellCooldownBeSecret(61304)
canaccessvalue(startTime)
canaccessvalue(duration)
canaccessvalue(modRate)
```

For the fallback, capture:

```text
canaccessvalue(UnitAttackSpeed("player"))
baseSwing
currentSwing
estimatedGCD
direct/estimated/cached source
```

Test at minimum:

1. outside combat and open-world combat;
2. encounter combat and Mythic+;
3. arena and battleground;
4. ordinary and one-second-GCD specs;
5. haste changes, attack-speed-only effects, and weapon swaps;
6. instant, cast-time, channelled, empowered, item, and macro actions;
7. off-GCD abilities mixed into every rotation;
8. `SPELL_SECRECY_CHANGED` and forced restriction states where supported;
9. repeated starts/stops/resets and `/reload`;
10. exact versus estimated metric output against a recorded manual timeline.

Issues #1 and #5 are release gates.
