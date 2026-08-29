# GCD runtime evidence contract

## Question

Does `C_Spell.GetSpellCooldown(61304)` provide ordinary usable numerical GCD timing in every supported combat restriction state, or must GCD Optimizer retain an estimated fallback?

## Current evidence

### Project/runtime history

The pre-update source states that numerical GCD cooldown values could become Secret in Midnight combat. It implements an out-of-combat `UnitAttackSpeed` baseline, a current/base swing ratio, cast-to-cast EWMA, and a last-stable fallback. The repository split does not preserve the exact original build, error text, or restriction context behind that redesign.

### Blizzard/community history

Blizzard-origin addon-engineering notes list `61304` among cooldowns flagged non-secret. WoWUIDev discussions in January, February, and May 2026 describe it as intentionally whitelisted and show direct reads in combat-oriented code.

### Current generated contract

In build `12.1.0.69497`:

- `C_Spell.GetSpellCooldown` remains restriction-sensitive;
- `SpellCooldownInfo.startTime`, `duration`, and `modRate` are not individually marked `NeverSecret`;
- `isActive` and `isEnabled` are `NeverSecret`;
- `isOnGCD` is `NeverSecret`, but documented as reliable only while responding to `SPELL_UPDATE_COOLDOWN`;
- `UnitAttackSpeed` is also restriction-sensitive.

## Interpretation

The documented whitelist is strong evidence of Blizzard's intended policy. It is not sufficient evidence to delete a fallback that exists because of contrary project runtime behavior. Possible explanations include a historical pre-whitelist build, a hotfix/regression, a restriction-specific exception, tainted execution, or an incorrect earlier diagnosis. The current repository does not yet distinguish them.

## Probe

Run in every target context. `pcall` below is diagnostics only.

```lua
local ID = 61304
local LEVEL = {
    [Enum.SecrecyLevel.NeverSecret] = "NeverSecret",
    [Enum.SecrecyLevel.AlwaysSecret] = "AlwaysSecret",
    [Enum.SecrecyLevel.ContextuallySecret] = "ContextuallySecret",
}

local function accessible(value)
    if canaccessvalue then return canaccessvalue(value) end
    if issecretvalue then return not issecretvalue(value) end
    return true
end

local function readField(info, key)
    local ok, value = pcall(function() return info and info[key] end)
    if not ok then return "READ_ERROR" end
    if not accessible(value) then return "INACCESSIBLE" end
    return type(value) .. ":" .. tostring(value)
end

local version, build, buildDate, interface = GetBuildInfo()
local info = C_Spell.GetSpellCooldown(ID)
local mh = UnitAttackSpeed and UnitAttackSpeed("player")

print("GCDPROBE", version, build, buildDate, interface)
print("hasRestrictions", C_Secrets.HasSecretRestrictions())
print("generalCooldownSecret", C_Secrets.ShouldCooldownsBeSecret())
print("policy", LEVEL[C_Secrets.GetSpellCooldownSecrecy(ID)])
print("secretNow", C_Secrets.ShouldSpellCooldownBeSecret(ID))
print("startTime", readField(info, "startTime"))
print("duration", readField(info, "duration"))
print("modRate", readField(info, "modRate"))
print("isActive", readField(info, "isActive"))
print("isOnGCD", readField(info, "isOnGCD"))
print("attackSpeed", accessible(mh) and tostring(mh) or "INACCESSIBLE")
```

## Context matrix

| Context | Build | Policy | Secret now | start/duration accessible | attack speed accessible | Tainted execution | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Outside combat | | | | | | | |
| Open-world combat | | | | | | | |
| Encounter | | | | | | | |
| Mythic+ | | | | | | | |
| Arena | | | | | | | |
| Battleground | | | | | | | |

## Acceptance rules

- Direct-only design is allowed only if the full supported matrix proves ordinary numeric access and repeated testing survives hotfix/build changes.
- Attack-speed fallback is allowed only when its inputs are accessible and calibration error is measured for relevant specs/effects.
- A source failure downgrades confidence; it must not silently fabricate exact data.
- Exact latency/SQW claims require exact or independently validated timing evidence.
