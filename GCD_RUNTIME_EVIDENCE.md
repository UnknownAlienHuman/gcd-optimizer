# GCD runtime evidence contract

## Status

- Source target: Retail `12.1.5`, Interface `120105`.
- Deterministic source tests: **PASS**.
- Named-build in-game matrix: **NOT-RUN**.

The unresolved question is whether numerical fields from `C_Spell.GetSpellCooldown(61304)` remain ordinary in every supported combat/restriction context. Project history says they did not; Blizzard-origin notes describe a whitelist. The hybrid source model remains until named-build evidence resolves the conflict.

## Probe

Run with taint/restriction context recorded. `pcall` is error containment only; every returned value is still gated before use.

```lua
local ID = 61304

local function accessible(value)
  if canaccessvalue then return canaccessvalue(value) end
  if issecretvalue then return not issecretvalue(value) end
  return true
end

local function accessibleTable(value)
  if not accessible(value) then return false end
  if type(value) ~= "table" then return false end
  if canaccesstable and not canaccesstable(value) then return false end
  return true
end

local function show(value)
  if not accessible(value) then return "INACCESSIBLE" end
  return type(value) .. ":" .. tostring(value)
end

local function readField(info, key)
  if not accessibleTable(info) then return "TABLE_INACCESSIBLE" end
  local ok, value = pcall(function() return info[key] end)
  if not ok then return "READ_ERROR" end
  return show(value)
end

local version, build, buildDate, interface = GetBuildInfo()
local okCooldown, info = pcall(C_Spell.GetSpellCooldown, ID)
local okSwing, mainHand = pcall(UnitAttackSpeed, "player")

print("GCDPROBE", version, build, buildDate, interface)
print("cooldownCall", tostring(okCooldown))
print("startTime", readField(info, "startTime"))
print("duration", readField(info, "duration"))
print("modRate", readField(info, "modRate"))
print("isActive", readField(info, "isActive"))
print("isOnGCD", readField(info, "isOnGCD"))
print("attackSpeedCall", tostring(okSwing))
print("attackSpeed", show(mainHand))

if C_Secrets then
  if C_Secrets.HasSecretRestrictions then
    print("hasRestrictions", show(C_Secrets.HasSecretRestrictions()))
  end
  if C_Secrets.ShouldCooldownsBeSecret then
    print("generalCooldownSecret", show(C_Secrets.ShouldCooldownsBeSecret()))
  end
  if C_Secrets.GetSpellCooldownSecrecy then
    print("policy", show(C_Secrets.GetSpellCooldownSecrecy(ID)))
  end
  if C_Secrets.ShouldSpellCooldownBeSecret then
    print("secretNow", show(C_Secrets.ShouldSpellCooldownBeSecret(ID)))
  end
end
```

## Context matrix

For every row record exact version, build, Interface, date, spec, equipment, taint state, and whether `SPELL_SECRECY_CHANGED` fired.

| Context | Build | start/duration/modRate | isActive | attack speed | Source observed | Errors/taint | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Outside combat | | | | | | | |
| Open-world combat | | | | | | | |
| Encounter | | | | | | | |
| Mythic+ | | | | | | | |
| Arena | | | | | | | |
| Battleground | | | | | | | |

## Behavioral matrix

Test separately:

- ordinary and one-second base-GCD profiles;
- instant, cast-time, channelled, and empowered actions;
- off-GCD actions mixed into each rotation;
- haste changes, attack-speed-only effects, weapon swaps, and spec changes;
- direct → estimated → direct transitions;
- login, `/reload`, start/stop/reset, combat auto-start/stop;
- SpellQueueWindow control in and out of combat;
- repeated sessions with no Lua or taint errors.

Compare exact/estimated source counts and accepted starts against a recorded manual timeline.

## Acceptance rules

- Direct timing is exact only when every consumed numeric field is accessible and valid.
- Event fallback requires confirmed generic-GCD activity plus a valid swing calibration.
- Cached duration never creates a start.
- Estimated and ambiguous samples never enter exact latency/SQW evidence.
- A source-test PASS is not a live-client PASS.
