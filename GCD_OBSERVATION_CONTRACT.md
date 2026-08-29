# GCD observation contract

## Compliance boundary

GCD Optimizer observes only the generic global-cooldown state that the World of Warcraft client exposes as ordinary accessible values. It does not treat API availability as a permanent entitlement and does not reconstruct data that the client marks Secret or otherwise makes inaccessible.

The runtime contract is:

1. Query the public spell-cooldown API for the generic GCD spell (`61304`).
2. Check `C_Secrets.ShouldSpellCooldownBeSecret(61304)` when that predicate exists.
3. Gate the returned cooldown object and every consumed field with `canaccessvalue`/`canaccessallvalues` before branching, comparing, calculating, formatting, indexing, logging, persisting, or forwarding it.
4. Distinguish a clean `inactive` cooldown from `restricted`, `unavailable`, and `malformed` observations.
5. Stop the measurement segment on any non-observable state. Never bridge that interval by extrapolation or retroactive counting.
6. Use the accessible cooldown `startTime` as the timing anchor and account for `modRate` when deriving wall-clock duration.

`UNIT_SPELLCAST_SUCCEEDED`, `SPELL_UPDATE_COOLDOWN`, and `ACTIONBAR_UPDATE_COOLDOWN` are wake-up signals only. None proves that a spell triggered the GCD.

## What the addon may claim

When the fields remain accessible, the addon may report that a generic GCD started, its accessible duration, and aggregate cadence over an observable segment.

## What the addon must not claim

The addon cannot prove which spell or input caused a GCD after discarding action payloads. Press-to-GCD matching is an estimate. Multiple plausible presses make the sample ambiguous and must exclude it from exact input-lead, latency, and SpellQueueWindow recommendations.

The addon must not recover identity or hidden state from spell/action payloads, macro text, targets, combat log, UI error text, protected-frame state, unit-stat reconstruction, timing side channels, or another restriction-sensitive API.

## Release evidence

Static tests establish only implementation invariants. A current-client test must record the exact version/build, Interface number, content context, `C_Secrets` result, field accessibility, Lua/taint errors, and detector debug state. A hotfix may change the policy without changing this repository.
