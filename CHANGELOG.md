# Changelog

## Unreleased — 2026-11-06

### Analytics and HUD follow-up

- Age SQW evidence by all recent accepted starts, including ambiguous/unobserved input. Use the same fresh sample set for search and lead buffer; late-only input no longer produces a queue-window recommendation.
- Include the configured maximum in the SQW search and report coverage for the returned value. Check the sorted-lead scan against an independent exhaustive reference over 120 deterministic datasets.
- Use a coherent ten-second live verdict window with its own attributable sample count, excluding pre-boundary cycles. Preserve full-segment counters beyond the bounded rolling log; percentile samples stay bounded and are not whole-fight quantiles.
- Remove the surviving old-hook inactivity verdict and ambiguity-as-player-error inference. Keep final verdicts independent of later combat/time changes; use public combat-lockdown state rather than unit combat data for presentation mode.
- Close transient windows and cancel HUD work on actual hide; reject stale ticker callbacks and stale menu Start actions. Remove unused distribution getters after consolidating context collection.
- Accumulate sub-millisecond duration corrections against the last forwarded value and invalidate a mismatched swing calibration without losing the latest direct display value.
- Add `tests/test_review.lua`: 23 cases / 280 assertions, passing alongside all three existing suites under Lua 5.3 and 5.4. Live client, taint, rendering and performance remain NOT-RUN.

### Continuity repair

- Break exact cycle/input continuity on restricted, unavailable, malformed, or secrecy-policy boundaries; preserve observed start counts and deduplication. Recovery and estimate upgrades cannot backfill a blind interval.
- Drive possible-GCD integration from detector observations, not HUD reads. Rendering is read-only; unavailable intervals contribute no capacity. A bounded rate history and last-action checkpoint freeze the final idle-tail cut independently of HUD visibility.
- Reject stale detector/fallback callbacks before they query APIs or touch replacement timer handles; standalone reset also cancels HUD work.
- Invalidate the old swing calibration when a new exact GCD has no readable swing sample, retaining only the last stable display duration.
- Repair non-finite numeric settings before timers, bounded buffers, or SQW search use them.
- Add `tests/test_continuity.lua` for these regressions. All three suites pass under standalone Lua 5.3 and 5.4; the in-game/taint/performance matrix remains NOT-RUN.

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
