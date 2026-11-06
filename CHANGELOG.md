# Changelog

## 0.6.0-midnight-12.1.5 — 2026-11-06

### Observation model

- Updated the addon to Retail 12.1.5 / Interface `120105`.
- Centralized restriction-sensitive `61304` and `UnitAttackSpeed` reads.
- Normalized exact cooldown duration by `modRate`.
- Added explicit `DIRECT_EXACT`, `ESTIMATED_SWING`, and `CACHED_LOW_CONFIDENCE` sources.
- Replaced the fixed 1.5-second assumption with direct GCD/swing-pair calibration, including one-second profiles.
- Invalidated swing calibration on equipment and specialization changes while preserving the last stable display value.
- Removed the nonexistent `C_Spell.DoesSpellTriggerGlobalCooldown` branch.
- Required confirmed generic-GCD activity before an event timestamp can become an estimated start.
- Added delayed fallback, continuous-active cadence dedupe, and estimated-to-direct upgrade without double counting.
- Prevented repeated same-start polling from recalibrating swing state or downgrading exact timing.

### Metrics and UI

- Separated approximate cadence from exact latency/SQW evidence.
- Classified zero press candidates as unobserved and multiple candidates as ambiguous.
- Excluded estimated, unobserved, and ambiguous cycles from exact recommendations.
- Removed no-hook/no-press inference as proof of AFK.
- Bounded press attribution after the previous GCD start, even with an extreme SpellQueueWindow value.
- Stopped unchanged exact polls from bypassing the HUD refresh cadence.
- Rebuilt the HUD around source quality and evidence counts.
- Guarded SpellQueueWindow changes during combat lockdown.
- Fixed failure-category rendering and removed stale analysis paths.

### Lifecycle and validation

- Made cached/default durations display-only and non-integrable.
- Preserved one-owner bounded detector/HUD timers with explicit cancellation.
- Added deterministic Lua tests for access states, modRate, one-second calibration, attribution boundaries, off-GCD rejection, source priority, transition upgrade, refresh suppression, and duplicate suppression.
- Removed obsolete metrics wrappers, state, and configuration that no longer had a runtime consumer.
- Live 12.1.5 context matrix remains NOT-RUN.

## Unreleased correction — 2026-08-29

- Restored the attack-speed fallback after an unjustified direct-only migration.
- Restored event-derived candidate starts for contexts where numerical `61304` timing was unavailable.
- Preserved Core initialization, single command ownership, SavedVariables migration, payload-free input/failure tracking, and obsolete API cleanup.
- Documented the conflict between whitelist notes and project runtime history.

## 0.5.0-midnight-12.1 — 2026-08-27

- Updated to Retail 12.1.0 / Interface `120100`.
- Centralized lifecycle and `/gcdopt` ownership.
- Excluded the developer harness from production load order.
- Removed combat-log/raw UI-error failure inference and obsolete `GetMouseFocus` use.
