-- GCDOptimizer_Test.lua
-- Developer-only diagnostics. This file is intentionally excluded from the
-- production TOC. Add it manually while developing; it owns /gcdopttest, never
-- /gcdopt.

local _, NS = ...
local U = NS.Util

local function Print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGCDOptTest|r " .. tostring(message))
  end
end

local function PrintEstimator()
  if not (NS.GCDEstimator and NS.GCDEstimator.DebugSnapshot) then
    Print("Estimator unavailable")
    return
  end
  local snapshot = NS.GCDEstimator:DebugSnapshot()
  Print(string.format(
    "gcd=%.3f source=%s samples=%d last=%.3f",
    snapshot.lastPred or 0,
    tostring(snapshot.source or "unknown"),
    snapshot.sampleCount or 0,
    snapshot.lastSampleAt or 0
  ))
end

local function PrintCooldownSecrecy()
  if not (C_Secrets and C_Secrets.GetSpellCooldownSecrecy and C_Secrets.ShouldSpellCooldownBeSecret) then
    Print("C_Secrets cooldown predicates unavailable")
    return
  end

  local policy = C_Secrets.GetSpellCooldownSecrecy(U.GCD_SPELL_ID)
  local secretNow = C_Secrets.ShouldSpellCooldownBeSecret(U.GCD_SPELL_ID)
  if not U.CanAccessValues(policy, secretNow) then
    Print("61304 cooldown policy is inaccessible in this context")
    return
  end

  Print(string.format(
    "61304 cooldownPolicy=%s secretNow=%s",
    tostring(policy),
    tostring(secretNow)
  ))
end

SLASH_GCDOPTTEST1 = "/gcdopttest"
SlashCmdList.GCDOPTTEST = function(rawMessage)
  local command = (rawMessage or ""):lower():match("^%s*(.-)%s*$")
  if command == "debug" then
    PrintEstimator()
  elseif command == "secrecy" then
    PrintCooldownSecrecy()
  else
    Print("Commands: /gcdopttest debug | secrecy")
  end
end
