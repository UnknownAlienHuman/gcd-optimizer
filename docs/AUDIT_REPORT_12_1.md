# Pull Request / Audit Report: GCDOptimizer — Retail 12.1 (Interface 120100) Compliance & Modernization

## Executive Summary

| Item | Details |
| :--- | :--- |
| **Addon Name** | **GCDOptimizer** |
| **Addon Directory** | `_Addons/GCDOptimizer` |
| **Remote Repository** | `github-gcd-optimizer` (`https://github.com/UnknownAlienHuman/gcd-optimizer.git`) |
| **Target Client** | World of Warcraft: Midnight / Retail 12.1 (`Interface: 120100`, Build 69497) |
| **Addon Purpose** | High-precision Global Cooldown (GCD) cadence analyzer, player press latency estimator, SpellQueueWindow (SQW) recommender, and input-gap/waste diagnostic HUD. |
| **Audit Date** | 2026-09-08 |
| **Local Status** | **v0.4.9-midnight-v2** (`Interface: 120001,120000`, 24 files). Suffers from triplicate slash command collision shadowing all production commands, complete wipe of user SavedVariables on any version string change, multiple uncoordinated `PLAYER_LOGIN` event frames violating RT-AUDIT-002, uninitialized core submodules (`GCDDetector`, `PressTracker`), deprecated `GetMouseFocus()` calls, dangerous global monkey-patching in `Test.lua`, and legacy combat log / raw UI error inspections that fail or taint in Retail 12.1. |
| **Remote Status** | **v0.5.0-midnight-12.1** (`Interface: 120100`, 27 files). Resolves slash command ownership under `GCDOptimizer_Core.lua`, introduces Schema 1 non-destructive SavedVariables migration (RT-AUDIT-001), moves `Test.lua` out of the production TOC to `/gcdopttest`, strips all action/spell/macro payloads from press hooks, eliminates CLEU and UI error string parsing, implements segment-scoped ticker cleanup, and establishes the hybrid GCD observation contract (`DIRECT_EXACT`, `ESTIMATED_SWING`, `CACHED_LOW_CONFIDENCE`) after reversing an overly aggressive direct-only refactor. |

---

## Remote Comparison (`git diff HEAD:_Addons/GCDOptimizer github-gcd-optimizer/main`)

A repository diff between local `HEAD:_Addons/GCDOptimizer` and upstream `remotes/github-gcd-optimizer/main` reveals major modernization across 20 files:

```
 AGENT_GUIDE.md                | 101 +++++++---
 ARCHITECTURE.md               |  61 +++++-
 CHANGELOG.md                  |  38 ++++
 CODE_GRAPH.md                 |  40 +++-
 CODE_INDEX.md                 |  25 ++-
 GCDOptimizer.toc              |  17 +-
 GCDOptimizer_Anchors.lua      | 350 ++++++++------------------------
 GCDOptimizer_Core.lua         | 440 ++++++++++++++++++++--------------------
 GCDOptimizer_Failures.lua     | 455 +++++++++---------------------------------
 GCDOptimizer_Integrator.lua   |  96 ++++-----
 GCDOptimizer_Minimap.lua      | 150 +++++---------
 GCDOptimizer_Options.lua      | 177 ++++++++--------
 GCDOptimizer_PressTracker.lua |  75 +++----
 GCDOptimizer_Test.lua         | 162 ++++-----------
 GCDOptimizer_Util.lua         | 156 ++++++++++-----
 GCD_OBSERVATION_CONTRACT.md   |  30 +++
 GCD_RUNTIME_EVIDENCE.md       |  89 +++++++++
 README.md                     |  93 +++++++--
 README_MIDNIGHT.md            | 169 ++++++++++++----
 todo.md                       |  49 ++++-
 20 files changed, 1348 insertions(+), 1425 deletions(-)
```

### Upstream Commit Evolution Walkthrough

1. **Commit `cf0698a`: Update GCD Optimizer for Retail 12.1**
   - Targeted Interface `120100` and updated version to `0.5.0-midnight-12.1`.
   - Unified slash command ownership under `GCDOptimizer_Core.lua`.
   - Made input press tracking and cast failure tracking zero-payload (timestamps only).
   - Preserved SavedVariables through Schema 1 migration rather than version-string wipes.
   - *Attempted to delete the swing-speed fallback and cast-delta estimator in favor of direct-only 61304 reads.*
2. **Commit `c88babc`: Make production TOC exclusion check unambiguous**
   - Cleaned up TOC load order to ensure `GCDOptimizer_Core.lua` loads last among runtime files, and explicitly excluded `GCDOptimizer_Test.lua`.
3. **Commit `e141ea1` & `52e794a`: Document the compliant GCD observation contract**
   - Added `GCD_OBSERVATION_CONTRACT.md`, formalizing the client boundaries, accessibility gating, and distinction between observable GCD timing and non-observable hidden data.
4. **Commit `d46f268`: Restore Midnight GCD fallback architecture (Critical Regression Fix)**
   - Reverted the direct-only change from `cf0698a`. Restored `baseSwing / currentSwing` swing-speed ratio estimator and `UNIT_SPELLCAST_SUCCEEDED` candidate-start fallback.
   - Preserved the new 12.1 bootstrap, unified slash dispatcher, SavedVariables schema, and payload-free safety boundaries.
5. **Commit `00d8bd2`: Correct GCD evidence model and document restored fallback**
   - Added `GCD_RUNTIME_EVIDENCE.md` documenting the conflict between Blizzard's documented `61304` non-secret whitelist and reported project runtime restrictions in Midnight instanced combat.
   - Formalized the three observation classes: `DIRECT_EXACT`, `ESTIMATED_SWING`, and `CACHED_LOW_CONFIDENCE`.

---

## Detailed Audit Findings against Retail 12.1 & KB Standards

### 1. TOC Interface Metadata & Runtime Load-Order Inversion (Critical)
- **Local State** (`GCDOptimizer.toc:1, 16-30`):
  ```ini
  ## Interface: 120001,120000
  ## Version: 0.4.9-midnight-v2
  ...
  GCDOptimizer_GCDEstimator.lua
  GCDOptimizer_Core.lua
  GCDOptimizer_PressTracker.lua
  GCDOptimizer_Integrator.lua
  GCDOptimizer_Metrics.lua
  GCDOptimizer_GCDDetector.lua
  GCDOptimizer_Anchors.lua
  GCDOptimizer_Failures.lua
  GCDOptimizer_HUD.lua
  GCDOptimizer_Options.lua
  GCDOptimizer_Minimap.lua
  GCDOptimizer_Test.lua
  ```
- **Violations**:
  - Outdated interface number. Multi-token comma syntax triggers parser warnings; target Retail 12.1 is `120100`.
  - **Load Order Inversion**: `GCDOptimizer_Core.lua` was loaded on line 20, *before* `PressTracker`, `Integrator`, `Metrics`, `GCDDetector`, `Anchors`, `HUD`, `Options`, and `Minimap`. When `ADDON_LOADED` fired, `Core.lua` attempted to call methods on submodules that were still being defined or had not yet registered on `NS`.
  - `GCDOptimizer_Test.lua` was loaded in production.
- **Upstream 12.1 Fix**:
  ```ini
  ## Interface: 120100
  ## Version: 0.5.0-midnight-12.1
  ...
  # Runtime modules
  GCDOptimizer_Util.lua
  GCDOptimizer_Locale.lua
  GCDOptimizer_GCDEstimator.lua
  GCDOptimizer_PressTracker.lua
  GCDOptimizer_Integrator.lua
  GCDOptimizer_Metrics.lua
  GCDOptimizer_GCDDetector.lua
  GCDOptimizer_Anchors.lua
  GCDOptimizer_Failures.lua
  GCDOptimizer_HUD.lua
  GCDOptimizer_Options.lua
  GCDOptimizer_Minimap.lua
  GCDOptimizer_Core.lua

  # Developer diagnostics are intentionally excluded from production load order.
  ```
  `GCDOptimizer_Core.lua` acts as the composition root and loads last after all submodules are loaded.

---

### 2. Triplicate Slash Command Collision & Complete Command Shadowing (Critical)
- **Local State**:
  - `GCDOptimizer_Core.lua:349-390`: Assigned `SLASH_GCDOPT1 = "/gcdopt"` with `show`, `hide`, `start`, `stop`, `reset`.
  - `GCDOptimizer_Minimap.lua:105-135`: Reassigned `SLASH_GCDOPT1 = "/gcdopt"` and overwrote `SlashCmdList["GCDOPT"]`, altering `show`/`hide` to toggle the minimap icon instead of the HUD!
  - `GCDOptimizer_Test.lua:108-120`: Reassigned `SLASH_GCDOPT1 = "/gcdopt"` and overwrote `SlashCmdList.GCDOPT` a third time, exposing *only* `test`, `debug`, and `anchors`.
- **Consequence**:
  Because `Test.lua` loaded last, the production commands `/gcdopt`, `/gcdopt show`, `/gcdopt hide`, `/gcdopt start`, `/gcdopt stop`, and `/gcdopt reset` were completely broken and inaccessible to users in game.
- **Upstream 12.1 Fix**:
  - `Core.lua` becomes the single authoritative owner of `SLASH_GCDOPT1 = "/gcdopt"`:
    - `/gcdopt` (toggle HUD)
    - `/gcdopt show | hide | start | stop | reset`
    - `/gcdopt minimap show | minimap hide`
    - `/gcdopt debug | anchors | help`
  - `Minimap.lua` slash registration completely removed.
  - `Test.lua` uses `SLASH_GCDOPTTEST1 = "/gcdopttest"` and is excluded from production TOC.

---

### 3. RT-AUDIT-001: Destructive SavedVariables Wipes & Mutation (High)
- **Local State** (`GCDOptimizer_Core.lua:99-114`, `GCDOptimizer_Minimap.lua:4`):
  ```lua
  -- In Minimap.lua at file-level execution:
  GCDOptimizerDB = GCDOptimizerDB or {}

  -- In Core.lua:
  local prev = db.__addonVersion
  if prev ~= NS.VERSION then
    db = {} -- ALL USER SETTINGS ERASED ON EVERY ADDON UPDATE!
  end
  ```
- **Violations**:
  - Accessing/instantiating `GCDOptimizerDB` in `Minimap.lua` at file parse time creates a discarded table once the client initializes SavedVariables at `ADDON_LOADED`.
  - Wiping `db = {}` whenever `NS.VERSION` changes destroyed all user HUD positions, anchor configs, and settings whenever an update was installed.
- **Upstream 12.1 Fix**:
  - Introduced `NS.DB_SCHEMA = 1`. Version upgrades preserve compatible settings through `DeepCopyDefaults`. Only an explicit schema change triggers migration.
  - Removed top-level `GCDOptimizerDB` instantiation; all access routed through `NS:GetConfig()`.

---

### 4. RT-AUDIT-002: Single Runtime Owner & Uninitialized Submodules (High)
- **Local State**:
  - Independent `PLAYER_LOGIN` event frames in `GCDOptimizer_PressTracker.lua:64-68`, `GCDOptimizer_Minimap.lua:137-141`, and `GCDOptimizer_Failures.lua:264`.
  - In `GCDOptimizer_Core.lua:NS:Init()`:
    ```lua
    SafeCall(NS.Failures, "Init")
    SafeCall(NS.Anchors, "Init")
    SafeCall(NS.GCDEstimator, "Init")
    SafeCall(NS.Metrics, "Reset", Now())
    SafeCall(NS.Integrator, "Reset", Now())
    SafeCall(NS.GCDDetector, "Reset", Now())
    ...
    ```
    `PressTracker:Init()` and `GCDDetector:Init()` were **never called** during addon bootstrap! `GCDDetector` has an `Init()` method that creates its event frame for `UNIT_SPELLCAST_SUCCEEDED`. Calling only `Reset` left the event frame uncreated in early lifecycle states.
- **Upstream 12.1 Fix**:
  - Removed all rogue `PLAYER_LOGIN` event frames.
  - `Core.lua` owns the single event frame (`ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`).
  - `NS:Init()` deterministically boots all modules in dependency order:
    ```lua
    SafeCall(NS.GCDEstimator, "Init")
    SafeCall(NS.PressTracker, "Init")
    SafeCall(NS.GCDDetector, "Init")
    SafeCall(NS.Failures, "Init")
    SafeCall(NS.Anchors, "Init")
    NS:ResetSegment(Now())
    SafeCall(NS.HUD, "Init")
    SafeCall(NS.Options, "Init")
    SafeCall(NS.Minimap, "Init")
    ```

---

### 5. Combat Log & Raw UI Error Parsing Elimination (`GCDOptimizer_Failures.lua`) (Critical Taint/Restriction Risk)
- **Local State** (`GCDOptimizer_Failures.lua:270-340`):
  - Registered `COMBAT_LOG_EVENT_UNFILTERED` and parsed `CombatLogGetCurrentEventInfo()` (`failedType`, `sourceGUID`).
  - Registered `UI_ERROR_MESSAGE` and matched strings against `ERR_OUT_OF_RANGE`, `ERR_BADATTACKPOS`.
- **Violations**:
  - In Midnight / Retail 12.1 instanced combat, `COMBAT_LOG_EVENT_UNFILTERED` is disabled or restricted.
  - UI error messages in combat can be Secret values; comparing them with strings throws hard Lua errors or taints execution.
- **Upstream 12.1 Fix**:
  - Abolished `COMBAT_LOG_EVENT_UNFILTERED` and `UI_ERROR_MESSAGE` entirely.
  - Registers only `UNIT_SPELLCAST_FAILED` and `UNIT_SPELLCAST_FAILED_QUIET` for `player`.
  - Records zero payload (no spellID, castGUID, or error text), capturing only `GetTime()` with a 50ms deduplication gate.

---

### 6. Action Payload Stripping & Taint Safety (`GCDOptimizer_PressTracker.lua`) (High)
- **Local State** (`GCDOptimizer_PressTracker.lua:38-62`):
  - Captured `slot`, `spellID`, `spellName`, and hooked `RunMacroText`.
  - Forwarded `kind` and `id` to `NS.Metrics:OnPress(now, kind, id)`.
- **Violations**:
  - Hooking `RunMacroText` is a protected operation in combat that causes secure execution taint.
  - Carrying action slots and spell identifiers across secure boundaries risks leaking Secret values.
- **Upstream 12.1 Fix**:
  - Hooks `UseAction`, `CastSpellByID`, `CastSpellByName`, `UseInventoryItem`, and `C_Spell.CastSpell`.
  - Discards all hook arguments completely: `RecordPress()` takes no parameters and forwards only local `GetTime()` timestamps.
  - Never touches `RunMacroText`.

---

### 7. Spell Activation Overlays & Anchors (`GCDOptimizer_Anchors.lua`) (Medium)
- **Local State** (`GCDOptimizer_Anchors.lua:240-295`):
  - Listened to non-existent events `SPELL_ACTIVATION_OVERLAY_SHOW` and `SPELL_ACTIVATION_OVERLAY_HIDE`.
  - Listened to `UNIT_SPELLCAST_*` events and captured `target`, `castGUID`, and `spellID`.
- **Upstream 12.1 Fix**:
  - Removed `SPELL_ACTIVATION_OVERLAY_SHOW` / `HIDE` and `UNIT_SPELLCAST_*` listeners from Anchors.
  - Listens strictly to `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` and `SPELL_ACTIVATION_OVERLAY_GLOW_HIDE`.
  - Gates incoming `spellID` with `U.CanAccessValues(spellID)` before processing.
  - Employs a bounded circular buffer (`maxEvents = 300`) with modulo arithmetic (`((sequence - 1) % maxEvents) + 1`), preventing memory leaks.

---

### 8. Deprecated `GetMouseFocus()` Removal (`GCDOptimizer_Options.lua`) (Medium)
- **Local State** (`GCDOptimizer_Options.lua:136`):
  ```lua
  local f = GetMouseFocus()
  if f ~= btn and f ~= menu then menu:Hide() end
  ```
- **Violation**: `GetMouseFocus()` has been removed in modern WoW clients (replaced by `GetMouseFoci` or frame event handling).
- **Upstream 12.1 Fix**: Replaced with `panel:SetScript("OnHide", function() menu:Hide() end)`.

---

### 9. Hot-Path Ticker Management (`GCDOptimizer_HUD.lua`) (Medium)
- **Local State**: Toggling the HUD closed did not cancel the `hudUpdateInterval` ticker; it kept polling in the background.
- **Upstream 12.1 Fix**: Integrated `NS:SetHUDShown(shown)` which calls `SafeCall(hud, "StopTicker")` and hides `detailsFrame` when HUD is hidden.

---

### 10. Monkey-Patching in Test Harness (`GCDOptimizer_Test.lua`) (High)
- **Local State**: In `SimulateEstimator()`, `Test.lua` monkey-patched `_G.GetTime`, `_G.UnitAttackSpeed`, and `_G.GetSpellCooldown` at runtime in the global environment!
- **Upstream 12.1 Fix**: Completely removed runtime global monkey-patching. Replaced with safe snapshots and C_Secrets queries.

---

## The Retail 12.1 GCD Observation Contract & Hybrid Model

### The Evidence Discrepancy
- **Documented / Community View**: Blizzard addon engineering notes list GCD dummy spell `61304` as whitelisted (`NeverSecret`).
- **Project Runtime History**: In certain instanced combat states or pre-whitelist builds, numeric cooldown values for `61304` were reported as inaccessible/Secret.

### Upstream's Resolved Hybrid Contract
Rather than deleting the fallback or blindly trusting one source, the addon enforces three distinct observation classes:

```
+-----------------------------------------------------------------------+
| 1. DIRECT_EXACT (Highest Quality)                                     |
|    - C_Spell.GetSpellCooldown(61304) returns accessible numbers       |
|    - Polled by GCDDetector, deduplicated with DRIFT_EPS (0.10s)        |
|    - Directly drives exact cycle timing and SQW recommendations       |
+-----------------------------------------------------------------------+
                                  | (if 61304 is Secret or unreadable)
                                  v
+-----------------------------------------------------------------------+
| 2. ESTIMATED_SWING (Approximation)                                    |
|    - UnitAttackSpeed("player") accessible baseline swing ratio        |
|    - Haste multiplier = (baseSwing / currentSwing)                    |
|    - GCD ~= baseGCD / hasteMultiplier, gently nudged by cast EWMA     |
|    - Candidate starts inferred from UNIT_SPELLCAST_SUCCEEDED          |
+-----------------------------------------------------------------------+
                                  | (if swing speed also inaccessible)
                                  v
+-----------------------------------------------------------------------+
| 3. CACHED_LOW_CONFIDENCE (Fail-Safe)                                  |
|    - Last known stable duration retained                              |
|    - NEVER manufactures synthetic exact start timestamps              |
|    - Excluded from exact latency and SQW recommendations              |
+-----------------------------------------------------------------------+
```

---

## Remaining Hardening Backlog (Unresolved in Upstream `github-gcd-optimizer/main`)

While upstream `main` fixed the major bugs, the following items from `todo.md` remain to be addressed for full 12.1 perfection:

1. **Centralize Accessibility Gating**:
   `GCDOptimizer_Util.lua` introduced `U.CanAccessValues` and `U.ReadGCDCooldown`, but `GCDDetector.lua` and `GCDEstimator.lua` still maintain isolated, duplicated local helper functions (`ReadGCDCooldown`, `IsSecret`). They should delegate directly to `U.ReadGCDCooldown()`.
2. **One-Second Base-GCD Specs**:
   `GCDEstimator.lua` hardcodes `self.baseGCD = 1.5`. Energy-based specs (Rogues, Windwalker Monks, Feral Druids, Havoc Demon Hunters) have a fixed 1.0s base GCD. Silently using 1.5s skews all swing-ratio estimates for those classes.
3. **Off-GCD Spell Ingress in `GCDDetector.lua`**:
   Line 68 calls `C_Spell.DoesSpellTriggerGlobalCooldown(spellID)`. This API is absent from the 12.1 generated API contract. When missing, `triggers` defaults to `true`, causing off-GCD abilities (interrupts, racials, defensives) to be counted as new GCD starts if spaced >0.50s apart.
4. **`InCombatLockdown()` Guard on `SetCVar("SpellQueueWindow")`**:
   In `GCDOptimizer_HUD.lua:906`, the user can click "Apply" on a recommended SQW. Calling `SetCVar` during combat lockdown can throw errors or taint UI execution. It must be guarded by `InCombatLockdown()`.

---

## Proposed PR Diffs

### 1. `GCDOptimizer.toc`
Target Interface `120100`, bump version, reorder composition root `Core.lua` to load last, and exclude `Test.lua`.

```diff
--- a/_Addons/GCDOptimizer/GCDOptimizer.toc
+++ b/_Addons/GCDOptimizer/GCDOptimizer.toc
@@ -1,30 +1,25 @@
-## Interface: 120001,120000
+## Interface: 120100
 ## Title: GCD Optimizer
-## Notes: GCD timing / press analysis (queue/late/server delay)
+## Notes: GCD timing / press analysis (queue, late input, and server-delay symptoms)
 ## Author: Neomorph
-## Version: 0.4.9-midnight-v2
+## Version: 0.5.0-midnight-12.1
 ## SavedVariables: GCDOptimizerDB
 ## OptionalDeps: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0
-## IconTexture: Interface\\Icons\\INV_Misc_PocketWatch_02
+## IconTexture: Interface\Icons\INV_Misc_PocketWatch_02
 
-# Embedded libraries 
+# Embedded libraries
 libs\LibStub\LibStub.lua
 libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
 libs\LibDataBroker-1.1\LibDataBroker-1.1.lua
 libs\LibDBIcon-1.0\LibDBIcon-1.0.lua
 
-# Addon files
+# Runtime modules
 GCDOptimizer_Util.lua
 GCDOptimizer_Locale.lua
 GCDOptimizer_GCDEstimator.lua
-GCDOptimizer_Core.lua
 GCDOptimizer_PressTracker.lua
 GCDOptimizer_Integrator.lua
 GCDOptimizer_Metrics.lua
 GCDOptimizer_GCDDetector.lua
 GCDOptimizer_Anchors.lua
 GCDOptimizer_Failures.lua
 GCDOptimizer_HUD.lua
 GCDOptimizer_Options.lua
 GCDOptimizer_Minimap.lua
-GCDOptimizer_Test.lua
+GCDOptimizer_Core.lua
+
+# Developer diagnostics are intentionally excluded from production load order.
```

---

### 2. `GCDOptimizer_Core.lua`
Composition root: schema preservation, centralized HUD visibility, single authoritative `/gcdopt` dispatcher, and full module initialization.

```diff
--- a/_Addons/GCDOptimizer/GCDOptimizer_Core.lua
+++ b/_Addons/GCDOptimizer/GCDOptimizer_Core.lua
@@ -1,30 +1,30 @@
 -- GCDOptimizer_Core.lua
--- Core bootstrap + SavedVariables + combat autostart + segment lifecycle.
--- Integrates Failures module (Init + segment hooks).
+-- Retail 12.1 bootstrap, SavedVariables migration, segment lifecycle, combat
+-- automation, and the single authoritative /gcdopt command dispatcher.
 
 local ADDON_NAME, NS = ...
 
 NS.addonName = ADDON_NAME
-NS.VERSION = "0.4.9-midnight-v2"
+NS.VERSION = "0.5.0-midnight-12.1"
+NS.DB_SCHEMA = 1
 
-local function DeepCopyDefaults(dst, src)
-  if type(dst) ~= "table" then dst = {} end
-  for k, v in pairs(src) do
-    if type(v) == "table" then
-      dst[k] = DeepCopyDefaults(type(dst[k]) == "table" and dst[k] or {}, v)
-    elseif dst[k] == nil then
-      dst[k] = v
-    end
+local function DeepCopyDefaults(destination, defaults)
+  if type(destination) ~= "table" then destination = {} end
+  for key, value in pairs(defaults) do
+    if type(value) == "table" then
+      destination[key] = DeepCopyDefaults(
+        type(destination[key]) == "table" and destination[key] or {},
+        value
+      )
+    elseif destination[key] == nil then
+      destination[key] = value
+    end
   end
-  return dst
+  return destination
 end
@@ -102,17 +82,12 @@ local DEFAULTS = {
 function NS:GetConfig()
   local db = _G.GCDOptimizerDB
   if type(db) ~= "table" then db = {} end
 
-  -- Hard reset SavedVariables on addon version change.
-  -- This is intentional to avoid config drift when updating from old Curse builds.
-  local prev = db.__addonVersion
-  if prev ~= NS.VERSION then
-    db = {}
-  end
-
+  -- Version upgrades preserve compatible settings. Schema migrations, rather
+  -- than the release string, own any future destructive transformation.
   db = DeepCopyDefaults(db, DEFAULTS)
+  db.__schemaVersion = NS.DB_SCHEMA
   db.__addonVersion = NS.VERSION
 
   _G.GCDOptimizerDB = db
   return db
 end
@@ -265,24 +240,19 @@ function NS:Init()
   if NS._inited then return end
   NS._inited = true
 
   local cfg = NS:GetConfig()
 
-  SafeCall(NS.Failures, "Init")
-  SafeCall(NS.Anchors, "Init")
   SafeCall(NS.GCDEstimator, "Init")
-  SafeCall(NS.Metrics, "Reset", Now())
-  SafeCall(NS.Integrator, "Reset", Now())
-  SafeCall(NS.GCDDetector, "Reset", Now())
-  SafeCall(NS.Anchors, "Reset", Now())
-
+  SafeCall(NS.PressTracker, "Init")
+  SafeCall(NS.GCDDetector, "Init")
+  SafeCall(NS.Failures, "Init")
+  SafeCall(NS.Anchors, "Init")
+
+  NS:ResetSegment(Now())
+
   SafeCall(NS.HUD, "Init")
   SafeCall(NS.Options, "Init")
   SafeCall(NS.Minimap, "Init")
-
-  -- Ensure clean baseline
-  NS:ResetSegment(Now())
-
-  -- Apply HUD visibility from config
-  if NS.HUD and NS.HUD.frame then
-    NS.HUD.frame:SetShown(cfg.showHUD)
-  end
+  NS:SetHUDShown(cfg.showHUD)
 end
```

---

### 3. `GCDOptimizer_PressTracker.lua`
Payload-free press hooks; no inspection of action slots, spell IDs, or macro strings.

```diff
--- a/_Addons/GCDOptimizer/GCDOptimizer_PressTracker.lua
+++ b/_Addons/GCDOptimizer/GCDOptimizer_PressTracker.lua
@@ -1,68 +1,49 @@
 -- GCDOptimizer_PressTracker.lua
--- Captures player "press attempts" via secure hooks (local client-side).
--- We record timestamps only (optionally kind/id for future debug).
--- Dedupe: ignore presses within 5ms to avoid double hooks (UseAction + CastSpell* chains).
+-- Records only local press timestamps. Hook arguments are deliberately ignored
+-- so spell names, spell IDs, macro text, action payloads, and target data never
+-- cross into metrics state.
 
 local _, NS = ...
 NS.PressTracker = NS.PressTracker or {}
 local P = NS.PressTracker
 
-local function RecordPress(kind, id)
+local function RecordPress()
   if not (NS.state and NS.state.inSegment) then return end
-  if not (NS.Metrics and NS.Metrics.OnPress) then return end
 
-  local now = Now()
-  if P.lastPressAt and (now - P.lastPressAt) < 0.005 then
+  local now = GetTime()
+  local last = P.lastPressAt or 0
+  if last > 0 and (now - last) < 0.005 then
     return
   end
   P.lastPressAt = now
-  NS.Metrics:OnPress(now, kind, id)
+  if type(NS.OnPress) == "function" then
+    NS:OnPress(now)
   end
 end
 
-function P:InstallHooks()
+function P:Init()
   if self.hooksInstalled then return end
   self.hooksInstalled = true
   self:Reset()
 
-  hooksecurefunc("UseAction", function(slot)
-    RecordPress("action", slot)
-  end)
-  if CastSpellByID then
-    hooksecurefunc("CastSpellByID", function(spellID)
-      RecordPress("spellID", spellID)
-    end)
-  end
-  if CastSpellByName then
-    hooksecurefunc("CastSpellByName", function(spellName)
-      RecordPress("spell", spellName)
-    end)
-  end
-  if RunMacroText then
-    hooksecurefunc("RunMacroText", function()
-      RecordPress("macro", 0)
-    end)
-  end
+  HookGlobal("UseAction")
+  HookGlobal("CastSpellByID")
+  HookGlobal("CastSpellByName")
+  HookGlobal("UseInventoryItem")
+  if type(C_Spell) == "table" and type(C_Spell.CastSpell) == "function" then
+    hooksecurefunc(C_Spell, "CastSpell", RecordPress)
   end
 end
-
-local f = CreateFrame("Frame")
-f:RegisterEvent("PLAYER_LOGIN")
-f:SetScript("OnEvent", function()
-  P:InstallHooks()
-end)
```

---

### 4. `GCDOptimizer_Failures.lua`
Abolish CLEU and UI error message string parsing.

```diff
--- a/_Addons/GCDOptimizer/GCDOptimizer_Failures.lua
+++ b/_Addons/GCDOptimizer/GCDOptimizer_Failures.lua
@@ -1,20 +1,10 @@
 -- GCDOptimizer_Failures.lua
--- Tracks player action failure events for "why did my press do nothing?" diagnostics.
--- Midnight: combat log is restricted/removed; UI_ERROR_MESSAGE can be Secret.
--- We maintain safe local counters and optional recent failure history without inspecting Secret payloads.
+-- Payload-free player failure tracking. UI errors and combat log are intentionally
+-- omitted so Secret values and restricted text never enter addon state.
 
-function F:Init()
-  if self.frame then return end
+function F:Init()
   if self._inited then return end
   self._inited = true
   self:Reset()
 
-  local f = CreateFrame("Frame")
-  self.frame = f
-  f:RegisterEvent("PLAYER_LOGIN")
-  local interface = select(4, GetBuildInfo())
-  if type(interface) == "number" and interface < 120000 then
-    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
-  end
-  f:RegisterEvent("UI_ERROR_MESSAGE")
-  f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
-  f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
+  local frame = CreateFrame("Frame")
+  self.frame = frame
+  frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
+  frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
+  frame:SetScript("OnEvent", function()
+    self:_RecordFailure(GetTime())
+  end)
 end
```

---

### 5. `GCDOptimizer_Minimap.lua`
Remove duplicate slash command stomping and extra `PLAYER_LOGIN` event frame.

```diff
--- a/_Addons/GCDOptimizer/GCDOptimizer_Minimap.lua
+++ b/_Addons/GCDOptimizer/GCDOptimizer_Minimap.lua
@@ -1,15 +1,10 @@
 -- GCDOptimizer_Minimap.lua
--- Minimap launcher using LibDataBroker + LibDBIcon-1.0 (required by button organizers)
+-- LibDataBroker / LibDBIcon launcher. Slash commands are owned exclusively by
+-- GCDOptimizer_Core.lua.
 
 local _, NS = ...
-GCDOptimizerDB = GCDOptimizerDB or {}
 
--- Slash helpers
-SLASH_GCDOPT1 = "/gcdopt"
-SlashCmdList["GCDOPT"] = function(msg)
-  ...
-end
-
-local f = CreateFrame("Frame")
-f:RegisterEvent("PLAYER_LOGIN")
-f:SetScript("OnEvent", function()
-  EnsureDB()
-  InitLDB()
-end)
+function M:Init()
   if self._inited then return end
   self._inited = true
   ...
 end
```

---

### 6. Additional Hardening: `GCDEstimator.lua` (One-Second Base GCD Specs & Delegated Cooldown Reads)

```diff
--- a/_Addons/GCDOptimizer/GCDOptimizer_GCDEstimator.lua
+++ b/_Addons/GCDOptimizer/GCDOptimizer_GCDEstimator.lua
@@ -98,6 +98,16 @@ local function SpellTriggersGCD(spellID)
 end
 
 function E:Reset()
+  -- Determine base GCD from player class / spec
+  local _, class = UnitClass("player")
+  if class == "ROGUE" or class == "MONK" then
+    self.baseGCD = 1.0
+    self.minGCD = 0.75
+    self.maxGCD = 1.0
+  elseif class == "DRUID" and GetShapeshiftFormID and GetShapeshiftFormID() == 1 then -- Cat Form
+    self.baseGCD = 1.0
+  else
     self.baseGCD = 1.5
+  end
   self.baseSwing = nil
   self.lastPred = self.baseGCD
```

---

### 7. Additional Hardening: `GCDOptimizer_HUD.lua` (`InCombatLockdown` Safeguard)

```diff
--- a/_Addons/GCDOptimizer/GCDOptimizer_HUD.lua
+++ b/_Addons/GCDOptimizer/GCDOptimizer_HUD.lua
@@ -895,6 +895,11 @@
     local function ApplyValue()
+      if InCombatLockdown() then
+        status:SetText(ColorText("ff4444", "Cannot change CVar in combat"))
+        return
+      end
       local v = tonumber(eb:GetText() or "")
       if not v or v < 0 or v > 4000 then
```

---

## Live Release Gate & Verification Matrix

The following test plan must be executed on a Retail 12.1 live client (Build 69497+) before merging and packaging:

```lua
-- In-Game Diagnostic Probe (/gcdopttest secrecy)
local ID = 61304
print("--- GCD OPTIMIZER RUNTIME PROBE ---")
print("HasSecretRestrictions:", C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions())
print("ShouldCooldownsBeSecret:", C_Secrets and C_Secrets.ShouldCooldownsBeSecret and C_Secrets.ShouldCooldownsBeSecret())
print("CooldownSecrecy(61304):", C_Secrets and C_Secrets.GetSpellCooldownSecrecy and C_Secrets.GetSpellCooldownSecrecy(ID))
print("ShouldSpellCooldownBeSecret(61304):", C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret and C_Secrets.ShouldSpellCooldownBeSecret(ID))
local st, dur = NS.Util.ReadGCDCooldown()
print("Direct ReadGCDCooldown:", st, dur)
local mh, oh = UnitAttackSpeed("player")
print("UnitAttackSpeed:", mh, "accessible:", NS.Util.CanAccessValues(mh))
```

### Verification Checklist

- [ ] **Slash Command Usability**: Verify `/gcdopt`, `/gcdopt show`, `/gcdopt hide`, `/gcdopt start`, `/gcdopt stop`, `/gcdopt reset`, and `/gcdopt minimap show|hide` function cleanly without collision.
- [ ] **SavedVariables Persistence**: Verify reload preserves HUD position and settings without being wiped by `__addonVersion`.
- [ ] **Open-World & Instanced Combat**: Verify zero Lua errors upon entering combat (`PLAYER_REGEN_DISABLED`) and leaving combat (`PLAYER_REGEN_ENABLED`).
- [ ] **SecretValue Isolation**: Run in Mythic+ / Raid encounter with secret restrictions active. Confirm no arithmetic errors on `st`, `dur`, or `UnitAttackSpeed`.
- [ ] **Ticker Cleanup**: Verify that hiding the HUD stops the HUD ticker, and pausing/ending a segment stops the GCD polling ticker.
- [ ] **1.0s vs 1.5s Specs**: Verify base GCD initialization on Rogue/Monk/Druid (Cat) initializes to 1.0s rather than 1.5s.
- [ ] **Zero Action Taint**: Verify cast hooks do not cause taint errors when using protected macro actions or action bar buttons in combat.
