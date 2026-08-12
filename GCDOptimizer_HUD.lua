-- GCDOptimizer_HUD.lua
-- HUD + diagnostics + analysis (refresh configurable, default 5s).
-- Uses Metrics (queue/late/afk) + Failures (resource/target/cd/range/los attribution).
-- Uses Integrator piecewise possible GCD integration; Eff is integer-safe (<=100%).

local _, NS = ...
local U = NS.Util

NS.HUD = NS.HUD or {}
local H = NS.HUD

-- Metrics module reference:
-- Do not cache NS.Metrics at file-load time. Load order in Retail/Midnight can
-- leave it nil here, and the HUD would then permanently lose metrics access.
local function Metrics()
  return NS.Metrics
end

local max = math.max
local min = math.min


local function fmt1(x) return string.format("%.1f", x or 0) end
local function fmt2(x) return string.format("%.2f", x or 0) end
local function fmt3(x) return string.format("%.3f", x or 0) end
local function pct01(x) return string.format("%.1f%%", (x or 0) * 100) end
local function pct0(x) return string.format("%.0f%%", (x or 0) * 100) end
local function ms1(x_ms) return string.format("%.1fms", x_ms or 0) end

local function ColorText(hex, s)
  return "|cff" .. hex .. (s or "") .. "|r"
end
local TAG_COLORS = {
  ["OK"] = "00ff00",
  ["Stop sleeping!"] = "ff0000",
  ["Bad management"] = "ff8800",
  ["Bad server!"] = "cc66ff",
  ["Press faster!"] = "ff4444",
  ["Low sample"] = "ffff00",
}

-- Auto-fit frame width to content (rarely, to avoid per-frame cost).
-- Uses FontString:GetStringWidth() which is safe (non-protected) and does not touch "secret" APIs.
local function MaybeAutoFitWidth(self, now)
  if not self or not self.frame or not self.lines then return end
  local nextAt = self._nextSizeUpdate or 0
  if now < nextAt then return end
  -- Re-check at most twice per second.
  self._nextSizeUpdate = now + 0.5

  local maxW = 0
  for i = 1, #self.lines do
    local fs = self.lines[i]
    if fs and fs.GetStringWidth then
      local w = fs:GetStringWidth() or 0
      if w > maxW then maxW = w end
    end
  end

  -- Add padding for backdrop + left/right margins.
  local target = math.floor(maxW + 40 + 0.5)
  target = U.Clamp(target, 420, 900)

  local cur = self._lastWidth or (self.frame.GetWidth and self.frame:GetWidth()) or 560
  if math.abs(target - cur) >= 8 then
    self.frame:SetWidth(target)
    self._lastWidth = target
  end
end


local function SafeGetCVarNumber(name, fallback)
  local v = GetCVar(name)
  local n = tonumber(v)
  if not n then return fallback end
  return n
end

local function GetDynamicMicroCap(cfg)
  local sqwMs = SafeGetCVarNumber("SpellQueueWindow", 400)
  local recMs, recDiag
  local m = Metrics()
  if m and m.RecommendSpellQueueWindow then
    recMs, recDiag = m:RecommendSpellQueueWindow()
  end
  local recTag = "OK"
  if recDiag and recDiag.lowSample then
    recTag = "Low sample"
  elseif recDiag and (recDiag.multi or 0) >= (cfg.recommendMultiBadThr or 0.15) then
    recTag = "Bad management"
  elseif recDiag and (recDiag.noQueue or 0) >= (cfg.recommendSleepBadThr or 0.15) then
    recTag = "Stop sleeping!"
  end
  local recTagC = TAG_COLORS[recTag] and ColorText(TAG_COLORS[recTag], recTag) or recTag
  local sqwDisplay = string.format("%dms", math.floor(sqwMs + 0.5))
  if recMs and math.abs(sqwMs - recMs) >= (cfg.recommendDiffBadMs or 60) then
    sqwDisplay = ColorText("ff0000", sqwDisplay)
  end
  local sqw = sqwMs / 1000
  local margin = cfg.microCapMargin; if margin == nil then margin = 0.05 end
  local minV = cfg.microCapMin; if minV == nil then minV = 0.10 end
  local maxV = cfg.microCapMax; if maxV == nil then maxV = 0.40 end
  return U.Clamp(sqw + margin, minV, maxV), sqwMs, recMs, recDiag
end

local function Clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function pctOrDash(share, denom)
  if not denom or denom <= 0 then return "--" end
  return pct0(share or 0)
end

local function FailTag(topCat)
  if topCat == "RES" then return "resources" end
  if topCat == "CD"  then return "CD" end
  if topCat == "TGT" then return "target" end
  if topCat == "RNG" then return "range" end
  if topCat == "LOS" then return "LoS" end
  if topCat == "MOV" then return "moving" end
  return "other"
end

local function BuildAnalysisLine(args)
  -- Rule-based verdict, calibrated for two modes:
  -- * In combat: args are for the last 5 seconds (rolling).
  -- * Out of combat: args cover the whole segment (final report).

  local inCombat = args.inCombat and true or false
  local elapsedSec = args.elapsedSec or 0
  local idleSec = args.idleSec or 0
  local cycles = args.cycles or 0

  local durSec = args.durSec or args.dur or 0
  local lostG = args.lostG or 0
  local possible = args.possibleStarts or args.possible or 0
  local lostRate = (possible > 0) and (lostG / possible) or 0

  local wastedG = args.wastedG or 0
  local wastedPerMin = (durSec > 0) and (wastedG * 60 / durSec) or 0
  local tailG = args.tailG or 0

  local gapP90Ms = args.gapP90Ms or ((args.gapP90Sec or 0) * 1000)
  local gapNowSec = args.gapNowSec or 0
  local qMultiShare = args.qMultiShare or 0
  local noPressPct = args.noPressPct or 0
  local lateShare = args.lateShare or 0
  local lateP90Ms = args.lateP90Ms or 0

  local afterP90Ms = args.afterP90Ms or 0
  local qHit = args.qHit or 0
  local qDelayP90Ms = args.qDelayP90Ms or 0
  local afkDen = args.afkDen or 0
  local afkPressPct = args.afkPressPct or 0
  local afkTime = args.afkTime or 0
  local fTotal = args.fTotal or 0

  -- Confidence tag: based on segment elapsed time (works in combat too).
  local lowSample = elapsedSec < 10.0

  -- Thresholds (keep conservative to avoid false positives).
  local thr = {
    stopIdleSec = 2.0,
    stopNoPress = 0.18,
    badLostRate = 0.15,
    badGap90Ms  = 250.0,
    badLateShare= 0.45,
    badQMulti   = 0.12,
    badTailG    = 1.0,
    warnWstPerM = 6.0,
  }

  local function ms(x) return string.format("%.1fms", x or 0) end
  local function pct(x) return string.format("%.0f%%", (x or 0) * 100) end

  local function ColorTag(tag)
    -- "tag" is an internal English label (possibly with variants).
    local key = tag
    if key:find("^Bad management") then key = "Bad management" end
    if key:find("^Press faster") then key = "Press faster!" end
    if key:find("^Stop sleeping") then key = "Stop sleeping!" end
    if key:find("^Low sample") then key = "Low sample" end
    if key:find("^Bad server") then key = "Bad server!" end
    local hex = (TAG_COLORS and TAG_COLORS[key]) or (TAG_COLORS and TAG_COLORS.OK) or "ffffff"
    return ColorText(hex, NS:LT(tag))
  end

  local label = "OK"
  local labelKey = "OK"
  local parts = {}
  local function addPart(s)
    if #parts < 3 then parts[#parts + 1] = s end
  end

  -- 1) Hard inactivity / no meaningful input
  local stopSleep = inCombat and (elapsedSec >= 2.0) and ((idleSec >= thr.stopIdleSec) or (cycles >= 8 and noPressPct >= thr.stopNoPress))
  if stopSleep then
    if idleSec >= thr.stopIdleSec then
      label = "Stop sleeping!"
      labelKey = "Stop sleeping!"
      addPart(string.format("%s %.1fs", NS:L("ANL_IDLE", "Idle"), idleSec))
    else
      -- High no-press share usually means "press too late/rarely near GCD end", not true AFK.
      label = "Press faster!"
      labelKey = "Press faster!"
      addPart(string.format("%s %s", NS:L("MET_NO_PRESS", "No-press share"), pct(noPressPct)))
    end
  else
    -- 2) Server/latency weirdness: you do queue correctly, but queued-start delay is abnormally high.
    local badServer = (cycles >= 6 and qHit >= 0.65 and noPressPct < 0.12 and lateShare < 0.25 and qDelayP90Ms >= 220.0)
    if badServer then
      label = "Bad server!"
      labelKey = "Bad server!"
      addPart(string.format("%s %s", NS:L("MET_SDQ_P90", "Queued-start delay p90"), ms(qDelayP90Ms)))
    else
      -- 3) Bad management: you are attempting input during gaps, but starts are not happening.
      local badMgmt = false
      -- Live-gap management: you are actively pressing (idle is low), but no GCD start happens for a long time.
      if inCombat and gapNowSec >= 2.0 and idleSec <= 1.2 then
        badMgmt = true
      end
      if (afkDen >= 3 and afkPressPct >= 0.45) and (gapP90Ms >= thr.badGap90Ms or lostRate >= 0.10 or afkTime >= 0.7) then
        badMgmt = true
      end
      if (fTotal >= 3) and (lostRate >= 0.10 or afkTime >= 0.7) then
        badMgmt = true
      end
      if (afterP90Ms >= 800.0 and lateShare >= 0.25) and (gapP90Ms >= thr.badGap90Ms or lostRate >= 0.10) then
        badMgmt = true
      end
      -- Back-compat weak signals
      if qMultiShare >= thr.badQMulti then badMgmt = true end
      if tailG >= thr.badTailG then badMgmt = true end

      if badMgmt then
        labelKey = "Bad management"
        label = "Bad management"
      else
        -- 4) Press faster: late presses / micro waste dominate
        local pressFaster = false
        if (lostRate >= 0.08) or (gapP90Ms >= 150.0) or (wastedPerMin >= 4.0) then
          if qMultiShare < thr.badQMulti and tailG < thr.badTailG and afterP90Ms < 600.0 then
            pressFaster = true
          end
        end
        if pressFaster then
          label = "Press faster!"
          labelKey = "Press faster!"
        end
      end
    end
  end

  -- Expand bad management into a typed variant if failures are present.
  if labelKey == "Bad management" then
    local fTopCat = args.fTopCat
    local fTopShare = args.fTopShare or 0
    if fTotal >= 3 then
      local tag = (fTopCat and fTopShare >= 0.55) and FailTag(segTopCat) or "mixed"
      label = string.format("Bad management (%s)!", tag)
    else
      label = "Bad management!"
    end
  end

  -- Attach up to 3 dominant factors (short, stable).
  if labelKey == "Bad management" then
    if inCombat and gapNowSec >= 2.0 then addPart(string.format("%s %.1fs", NS:L("MET_GAP_NOW", "Current gap"), gapNowSec)) end
    if afkDen >= 3 then addPart(string.format("%s %s", NS:L("MET_AFK_PRESS", "Pressing during gaps"), pct(afkPressPct))) end
    if afterP90Ms >= 800.0 then addPart(string.format("%s %s", NS:L("MET_AFTER_P90", "After-GCD press p90"), ms(afterP90Ms))) end
    if gapP90Ms >= thr.badGap90Ms then addPart(string.format("%s %s", NS:L("MET_GAP_P90", "Gap p90"), ms(gapP90Ms))) end
    if lostRate >= thr.badLostRate then addPart(string.format("%s %s", NS:L("ANL_LOST_RATE", "Lost rate"), pct(lostRate))) end
  elseif labelKey == "Press faster!" then
    if lateP90Ms and lateP90Ms > 0 then addPart(string.format("%s %s", NS:L("MET_LATE_P90", "Late press p90"), ms(lateP90Ms))) end
    if wastedPerMin >= 4.0 then addPart(string.format("%s %.1f", NS:L("MET_WASTED_PM", "Wasted per min"), wastedPerMin)) end
  end

  local head
  local tagKeyOut = labelKey
  if lowSample then
    -- Low sample is a confidence warning, not a verdict suppressor.
    head = ColorTag("Low sample")
    if labelKey ~= "OK" then
      head = head .. " " .. ColorTag(label)
    else
      tagKeyOut = "Low sample"
    end
  else
    head = ColorTag(label)
  end

  local tail = ""
  if #parts > 0 then tail = " (" .. table.concat(parts, ", ") .. ")" end
  return head .. tail, tagKeyOut
end


function H:Init()
  local cfg = NS:GetConfig()

  if self.frame then
    self.frame:SetShown(cfg.showHUD)
    if cfg.showHUD then
      self:StartTicker()
      self:Update(true)
    else
      self:StopTicker()
      if self.detailsFrame then self.detailsFrame:Hide() end
    end
    return
  end

  -- =========================
  -- Mini HUD (always lightweight)
  -- =========================
  local f = CreateFrame("Frame", "GCDOptimizerHUD_Mini", UIParent, "BackdropTemplate")
  self.frame = f
  self.miniFrame = f

  local lineCount = 4
  local lineH = 18
  local paddingTop = 10
  local paddingBot = 10
  local height = paddingTop + paddingBot + lineCount * lineH

  f:SetSize(280, height)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  f:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(0, 0, 0, 0.85)
  f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, 4)
  closeBtn:SetScript("OnClick", function()
    cfg.showHUD = false
    f:Hide()
    if self.detailsFrame then self.detailsFrame:Hide() end
  end)

  local expBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  expBtn:SetSize(22, 18)
  expBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -2, -2)
  expBtn:SetText(">")
  self.expandBtn = expBtn

  -- Mini text lines
  self.lines = {}
  for i = 1, lineCount do
    local fs = f:CreateFontString(nil, "OVERLAY", (i == 4) and "GameFontNormal" or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -paddingTop - (i - 1) * lineH)
    fs:SetJustifyH("LEFT")
    fs:SetText("")
    self.lines[i] = fs
  end

  -- =========================
  -- Details HUD (full report, scrollable)
  -- =========================
  local df = CreateFrame("Frame", "GCDOptimizerHUD_Details", UIParent, "BackdropTemplate")
  self.detailsFrame = df

  df:SetSize(560, 420)
  df:SetPoint("TOP", f, "BOTTOM", 0, -10)
  df:SetMovable(true)
  df:EnableMouse(true)
  df:RegisterForDrag("LeftButton")
  df:SetScript("OnDragStart", function() df:StartMoving() end)
  df:SetScript("OnDragStop", function() df:StopMovingOrSizing() end)

  df:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  df:SetBackdropColor(0, 0, 0, 0.90)
  df:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
  df:Hide()

  local dfClose = CreateFrame("Button", nil, df, "UIPanelCloseButton")
  dfClose:SetPoint("TOPRIGHT", df, "TOPRIGHT", 4, 4)
  dfClose:SetScript("OnClick", function() df:Hide(); self:RefreshExpandButton() end)

  local title = df:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", df, "TOPLEFT", 12, -10)
  title:SetText("GCD Optimizer")

  local scroll = CreateFrame("ScrollFrame", nil, df, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", df, "TOPLEFT", 12, -36)
  scroll:SetPoint("BOTTOMRIGHT", df, "BOTTOMRIGHT", -30, 12)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)

  self.detailsScroll = scroll
  self.detailsContent = content
  self.detailRows = {}

  expBtn:SetScript("OnClick", function()
    self:ToggleDetails()
  end)

  -- Right-click context menu for both frames
  local function EnsureContextMenu()
    if self._ctxMenu then return self._ctxMenu end

    local catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:SetFrameStrata("DIALOG")
    catcher:Hide()

    local menu = CreateFrame("Frame", "GCDOptimizerHUD_ContextMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    menu:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.90)

    menu._catcher = catcher
    catcher:SetScript("OnMouseDown", function() menu:Hide() end)
    menu:SetScript("OnShow", function()
      catcher:Show()
      catcher:SetFrameLevel(menu:GetFrameLevel() - 1)
    end)
    menu:SetScript("OnHide", function() catcher:Hide() end)

    local pad = 10
    local w = 210
    local headerH = 16
    local btnH = 18
    local gap = 4

    menu:SetWidth(w)

    local header = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, -pad)
    header:SetText("GCD Optimizer")

    menu.header = header
    menu.buttons = {}

    function menu:SetItems(items)
      self._items = items or {}
      local n = #self._items
      local height = pad + headerH + gap + (n * btnH) + ((n - 1) * gap) + pad
      self:SetHeight(height)

      for i = 1, math.max(#self.buttons, n) do
        local b = self.buttons[i]
        local it = self._items[i]
        if it then
          if not b then
            b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
            b:SetHeight(btnH)
            b:SetWidth(w - pad * 2)
            self.buttons[i] = b
          end
          b:ClearAllPoints()
          local y = -pad - headerH - gap - ((i - 1) * (btnH + gap))
          b:SetPoint("TOPLEFT", self, "TOPLEFT", pad, y)
          b:SetText(it.text or "")
          b:SetEnabled(not it.disabled)
          b:SetScript("OnClick", function()
            self:Hide()
            if it.func then it.func() end
          end)
          b:Show()
        elseif b then
          b:Hide()
        end
      end
    end

    self._ctxMenu = menu
    return menu
  end

  function self:ShowContextMenu()
    local inSeg = NS.state and NS.state.inSegment
    local menu = EnsureContextMenu()

    local wantDetails = self.detailsFrame and self.detailsFrame:IsShown()
    local items = {
      {
        text = inSeg and NS:L("MENU_STOP", "Stop") or NS:L("MENU_START", "Start"),
        func = function()
          local t = GetTime()
          NS.state.autoCombat = false
          if inSeg then
            NS:PauseSegment(t)
          else
            NS:StartSegment(t)
          end
          self:Update(true)
        end
      },
      {
        text = NS:L("MENU_RESET", "Reset"),
        func = function()
          local t = GetTime()
          if inSeg then
            NS:ResetAndContinue(t)
          else
            NS:ResetSegment(t)
          end
          self:Update(true)
        end
      },
      {
        text = wantDetails and NS:L("MENU_COLLAPSE", "Collapse") or NS:L("MENU_EXPAND", "Expand"),
        func = function()
          self:SetDetailsShown(not wantDetails)
        end
      },
      {
        text = NS:L("MENU_SET_SQW", "Set SQW"),
        func = function()
          self:ShowSetSQW()
        end
      },
      {
        text = cfg.showHUD and NS:L("MENU_HIDE", "Hide") or NS:L("MENU_SHOW", "Show"),
        func = function()
          cfg.showHUD = not cfg.showHUD
          if self.frame then self.frame:SetShown(cfg.showHUD) end
          if cfg.showHUD then
            self:StartTicker()
            self:Update(true)
          else
            self:StopTicker()
            if self.detailsFrame then self.detailsFrame:Hide() end
          end
        end
      },
      {
        text = NS:L("MENU_CLOSE", "Close"),
        func = function()
          cfg.showHUD = false
          self:StopTicker()
          if self.frame then self.frame:Hide() end
          if self.detailsFrame then self.detailsFrame:Hide() end
        end
      },
    }

    menu:SetItems(items)
    menu:ClearAllPoints()
    local scale = UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x, y = (x / scale), (y / scale)
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 2, y - 2)
    menu:Show()
  end

  local function OnMouseDown(_, button)
    if button == "RightButton" then
      self:ShowContextMenu()
    end
  end
  f:SetScript("OnMouseDown", OnMouseDown)
  df:SetScript("OnMouseDown", OnMouseDown)

  -- initialize state blobs
  self.slowDiag = {
    analysis = "",
    analysisTag = "Low sample",
    qLeadP90 = 0,
    qDelayMed = 0,
    qDelayP90 = 0,
    lPressMed = 0,
    lPressP90 = 0,
    lAfterMed = 0,
    lAfterP90 = 0,
    qcPct = 0,
    qHitShare = 0,
    afkPressPct = 0,
    afkDen = 0,
    sdqPlusPct = 0,
    fTotal = 0,
    fResShare = 0,
    fTopCat = "OTH",
    fTopShare = 0,
  }

  f:SetShown(cfg.showHUD)
  self:RefreshExpandButton()

  if cfg.showHUD then
    self:StartTicker()
    self:Update(true)
  end
end



function H:RefreshExpandButton()
  if not self.expandBtn then return end
  local shown = self.detailsFrame and self.detailsFrame:IsShown()
  self.expandBtn:SetText(shown and "<" or ">")
end

function H:SetDetailsShown(show)
  if not self.detailsFrame then return end
  show = show and true or false
  if not (self.frame and self.frame:IsShown()) then show = false end
  self.detailsFrame:SetShown(show)
  self:RefreshExpandButton()
  self:Update(true)
end

function H:ToggleDetails()
  if not self.detailsFrame then return end
  self:SetDetailsShown(not self.detailsFrame:IsShown())
end

local function FormatMsInt(x)
  if not x then return "--" end
  return string.format("%dms", math.floor(x + 0.5))
end

function H:ColorTag(tag)
  if not tag or tag == "" then tag = "OK" end
  local key = tag
  if key:find("^Bad management") then key = "Bad management" end
  if key:find("^Press faster") then key = "Press faster!" end
  if key:find("^Stop sleeping") then key = "Stop sleeping!" end
  if key:find("^Low sample") then key = "Low sample" end
  if key:find("^Bad server") then key = "Bad server!" end
  local hex = (TAG_COLORS and TAG_COLORS[key]) or (TAG_COLORS and TAG_COLORS.OK) or "ffffff"
  return ColorText(hex, NS:LT(tag))
end

function H:RenderMini(s)
  if not self.lines then return end
  local t = (s.durSec ~= nil) and string.format("%.1fs", s.durSec) or "--"
  local gcd = s.gcdPredMs and FormatMsInt(s.gcdPredMs) or "--"
  local sqw = s.sqwMs and FormatMsInt(s.sqwMs) or "--"
  local rec = s.recMs and FormatMsInt(s.recMs) or "--"

  -- 1) Time | GCD
  self.lines[1]:SetText(string.format("%s: %s | %s: %s", NS:L("MET_TIME","Time"), t, NS:L("HUD_GCD","GCD"), gcd))
  -- 2) SQW
  self.lines[2]:SetText(string.format("%s: %s", NS:L("HUD_SQW","Spell Queue Window"), sqw))
  -- 3) Recommended SQW
  self.lines[3]:SetText(string.format("%s: %s", NS:L("HUD_REC_SQW","Recommended SQW"), rec))

  -- 4) Verdict
  local tag = s.verdictTag or "Low sample"
  self.lines[4]:SetText(string.format("%s: %s", NS:L("HUD_VERDICT","Verdict"), self:ColorTag(tag)))

  self:AutoFitMiniWidth()
end


function H:AutoFitMiniWidth(force)
  if not self.miniFrame or not self.lines then return end

  local now = GetTime()
  local nextAt = self._miniNextWAt or 0
  if (not force) and now < nextAt then return end
  self._miniNextWAt = now + 0.5

  local maxW = 0
  for i = 1, 4 do
    local fs = self.lines[i]
    if fs and fs.GetStringWidth then
      local w = fs:GetStringWidth() or 0
      if w > maxW then maxW = w end
    end
  end

  -- Padding + room for close/expand buttons.
  local target = math.floor(maxW + 12 + 12 + 70 + 0.5)
  target = U.Clamp(target, 240, 420)

  local cur = self._miniLastW or (self.miniFrame.GetWidth and self.miniFrame:GetWidth()) or target
  if force or math.abs(target - cur) >= 6 then
    self.miniFrame:SetWidth(target)
    self._miniLastW = target
  end
end

local function EnsureRow(self, idx)
  local r = self.detailRows[idx]
  if r then return r end

  r = CreateFrame("Frame", nil, self.detailsContent)
  r:SetHeight(18)

  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.label:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.label:SetWidth(260)
  r.label:SetJustifyH("LEFT")

  r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.value:SetPoint("LEFT", r.label, "RIGHT", 10, 0)
  r.value:SetJustifyH("LEFT")

  r.header = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.header:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.header:SetJustifyH("LEFT")
  r.header:Hide()

  r.desc = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.desc:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.desc:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  r.desc:SetJustifyH("LEFT")
  r.desc:Hide()

  self.detailRows[idx] = r
  return r
end

function H:RenderDetails(s)
  if not (self.detailsFrame and self.detailsFrame:IsShown() and self.detailsContent and self.detailsScroll) then return end

  local entries = {}

  local function Hdr(text, desc)
    entries[#entries+1] = { t="hdr", text=text }
    if desc and desc ~= "" then
      entries[#entries+1] = { t="desc", text=desc }
    end
  end
  local function KV(label, value)
    entries[#entries+1] = { t="kv", label=label, value=value }
  end

  local function pct0(x) return (x == nil) and "--" or string.format("%.0f%%", x*100) end
  local function pct1(x) return (x == nil) and "--" or string.format("%.1f%%", x*100) end
  local function ms1(x) return (x == nil) and "--" or string.format("%.1fms", x) end
  local function sec1(x) return (x == nil) and "--" or string.format("%.1fs", x) end
  local function num1(x) return (x == nil) and "--" or string.format("%.1f", x) end
  local function int(x) return (x == nil) and "--" or tostring(math.floor(x + 0.5)) end

  Hdr(NS:L("SEC_SUMMARY","Summary"), "")
  KV(NS:L("MET_TIME","Time"), sec1(s.durSec))
  KV(NS:L("HUD_GCD","GCD"), FormatMsInt(s.gcdPredMs))
  KV(NS:L("HUD_SQW","Spell Queue Window"), FormatMsInt(s.sqwMs))
  KV(NS:L("HUD_REC_SQW","Recommended SQW"), s.recMs and FormatMsInt(s.recMs) or "--")
  KV(NS:L("HUD_VERDICT","Verdict"), s.analysisLine or self:ColorTag(s.verdictTag or "Low sample"))

  Hdr(NS:L("SEC_LOSSES","Losses"), "")
  KV(NS:L("MET_EFF","Efficiency"), pct1(s.eff))
  KV(NS:L("MET_POSSIBLE","Possible GCDs"), int(s.possible))
  KV(NS:L("MET_ACTUAL","Actual GCDs"), int(s.actual))
  KV(NS:L("MET_LOST","Lost GCDs"), int(s.lostG))
  KV(NS:L("MET_WASTED","Wasted GCDs"), int(s.wastedG))
  KV(NS:L("MET_WASTED_PM","Wasted per min"), num1(s.wastedPerMin))
  KV(NS:L("MET_TAIL","Tail GCD"), num1(s.tailG))
  KV(NS:L("MET_GAP_P90","Gap p90"), ms1(s.gapP90Ms))
  KV(NS:L("MET_GAP_NOW","Current gap"), sec1(s.gapNowSec))

  Hdr(NS:L("SEC_INPUT","Queue & input"), "")
  KV(NS:L("MET_QHIT","Queue hits"), pct0(s.qHitShare))
  KV(NS:L("MET_QCOV","Queue coverage"), pct0(s.qcPct))
  KV(NS:L("MET_QUEUE_LEAD_P90","Queue lead p90"), ms1(s.qLeadP90Ms))
  KV(NS:L("MET_SDQ_PLUS","Start delay beyond cap"), pct0(s.sdqPlusPct))
  KV(NS:L("MET_AFK_DEN","AFK samples"), int(s.afkDen))
  KV(NS:L("MET_NO_PRESS","No-press share"), pct0(s.noPressPct))
  KV(NS:L("MET_AFK_PRESS","Pressing during gaps"), pct0(s.afkPressPct))
  KV(NS:L("MET_SDQ_P90","Queued-start delay p90"), ms1(s.qDelayP90Ms))
  KV(NS:L("MET_SDW_MED","Start delay median"), ms1(s.sdwMedMs))
  KV(NS:L("MET_SDW_P90","Start delay p90"), ms1(s.sdwP90Ms))

  Hdr(NS:L("SEC_LATENCY","Latency"), "")
  KV(NS:L("MET_LATE_MED","Late press median"), ms1(s.lateMedMs))
  KV(NS:L("MET_LATE_P90","Late press p90"), ms1(s.lateP90Ms))
  KV(NS:L("MET_AFTER_MED","After-GCD press median"), ms1(s.afterMedMs))
  KV(NS:L("MET_AFTER_P90","After-GCD press p90"), ms1(s.afterP90Ms))

  Hdr(NS:L("SEC_FAILS","Failures"), "")
  KV(NS:L("MET_FAIL_TOTAL","Total fails"), int(s.fTotal))
  KV(NS:L("MET_FAIL_TOP","Top fail reason"), s.fTopLabel or "--")
  KV(NS:L("MET_FAIL_TOP_SHARE","Top share"), pct0(s.fTopShare))
  KV(NS:L("MET_FAIL_RES_SHARE","Resource share"), pct0(s.fResShare))

  -- Render rows
  local y = 0
  local contentW = 520
  for i, e in ipairs(entries) do
    local r = EnsureRow(self, i)
    r:ClearAllPoints()
    r:Show()
    r:SetPoint("TOPLEFT", self.detailsContent, "TOPLEFT", 0, -y)
    r:SetPoint("TOPRIGHT", self.detailsContent, "TOPRIGHT", 0, -y)

    r.label:Hide()
    r.value:Hide()
    r.header:Hide()
    r.desc:Hide()

    if e.t == "hdr" then
      r:SetHeight(20)
      r.header:SetText(e.text or "")
      r.header:Show()
      y = y + 22
    elseif e.t == "desc" then
      r:SetHeight(14)
      r.desc:SetText(e.text or "")
      r.desc:Show()
      y = y + 16
    else
      r:SetHeight(18)
      r.label:SetText(e.label or "")
      r.value:SetText(e.value or "")
      r.label:Show()
      r.value:Show()
      y = y + 18
    end
  end

  -- Hide unused rows
  for i = #entries + 1, #self.detailRows do
    local r = self.detailRows[i]
    if r then r:Hide() end
  end

  self.detailsContent:SetSize(contentW, math.max(1, y + 10))
end

function H:ShowSetSQW()
  if self._sqwPopup and self._sqwPopup:IsShown() then return end

  local p = self._sqwPopup
  if not p then
    p = CreateFrame("Frame", "GCDOptimizerSQWPopup", UIParent, "BackdropTemplate")
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:SetSize(260, 130)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    p:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(0,0,0,0.95)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -10)
    title:SetText(NS:L("SQW_TITLE","Set Spell Queue Window"))

    local prompt = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    prompt:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    prompt:SetText(NS:L("SQW_PROMPT","Value (ms):"))

    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(80, 20)
    eb:SetPoint("TOPLEFT", prompt, "BOTTOMLEFT", 0, -6)
    eb:SetAutoFocus(true)
    eb:SetNumeric(true)
    p.editBox = eb

    local status = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("LEFT", eb, "RIGHT", 10, 0)
    status:SetText("")
    p.status = status

    local ok = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    ok:SetSize(90, 22)
    ok:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, 12)
    ok:SetText(NS:L("SQW_OK","OK"))
    p.okBtn = ok

    local cancel = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -12, 12)
    cancel:SetText(NS:L("OPT_CLOSE","Close"))
    cancel:SetScript("OnClick", function() p:Hide() end)

    local function ApplyValue()
      local v = tonumber(eb:GetText() or "")
      if not v or v < 0 or v > 4000 then
        status:SetText(ColorText("ff4444", NS:L("SQW_BAD_NUMBER","Bad number")))
        return
      end

      status:SetText("")
      ok:SetText(NS:L("SQW_OK","OK"))
      ok:SetScript("OnClick", nil)

      local okSet = pcall(function()
        SetCVar("SpellQueueWindow", tostring(math.floor(v + 0.5)))
      end)

      local cur = SafeGetCVarNumber("SpellQueueWindow", -1)
      if okSet and cur and cur >= 0 then
        -- Most clients apply instantly. If it doesn't stick, offer reload.
        if math.abs(cur - v) <= 1 then
          p:Hide()
          if NS.HUD then NS.HUD:Update(true) end
          return
        end
      end

      status:SetText(ColorText("ffff44", NS:L("OPT_RELOAD","Reload UI")))
      ok:SetText(NS:L("SQW_RELOAD","Reload UI"))
      ok:SetScript("OnClick", function() ReloadUI() end)
    end

    ok:SetScript("OnClick", ApplyValue)
    eb:SetScript("OnEnterPressed", ApplyValue)
    eb:SetScript("OnEscapePressed", function() p:Hide() end)

    self._sqwPopup = p
  end

  local cur = SafeGetCVarNumber("SpellQueueWindow", 400)
  p.okBtn:SetText(NS:L("SQW_OK","OK"))
  p.status:SetText("")
  p.editBox:SetText(tostring(cur or 400))
  p:Show()
  p.editBox:SetFocus()
  p.editBox:HighlightText()
end

function H:OnSegmentStart()
  -- Reset analysis state for a new segment.
  self.slowDiag = self.slowDiag or {}
  self.slowDiag.firstAt = GetTime()
  self.slowDiag.nextUpdate = 0
  self.slowDiag.lastCycles = -1
  self.slowDiag.analysis = ""
  self:StartTicker()
  self:Update()
end
function H:OnSegmentEnd() self:StopTicker(); self:Update(true) end
function H:OnGCDStart() self:Update() end
function H:OnRateUpdate() self:Update() end

function H:StartTicker()
  local cfg = NS:GetConfig()
  local interval = U.Clamp(cfg.hudUpdateInterval or 0.25, 0.10, 1.00)
  if self.ticker then self.ticker:Cancel() end
  self.ticker = C_Timer.NewTicker(interval, function() self:Update() end)
end

function H:StopTicker()
  if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

-- ---------------------------------------------------------------------------
-- Slow/diagnostic recomputation helpers (kept local to avoid globals/taint).
-- ---------------------------------------------------------------------------
local function RecomputeSlow(self, now, metrics, integ)
  self.slow = self.slow or { nextUpdate = 0, apm10 = 0, myGCDMed = 0, gapP90 = 0 }
  if now < (self.slow.nextUpdate or 0) then return end
  local refresh = self._refreshSec or 5
  self.slow.nextUpdate = now + refresh

  -- APM10: optional (may not exist in all builds)
  if metrics.GetAPM10 then
    self.slow.apm10 = metrics:GetAPM10(now) or 0
  end

  -- Median/typical GCD for display: prefer detector live median, else integrator prediction.
  if metrics.GetMedianGCD then
    self.slow.myGCDMed = metrics:GetMedianGCD() or (integ and integ.GetCurrentPredictedGCD and integ:GetCurrentPredictedGCD()) or 0
  else
    self.slow.myGCDMed = (integ and integ.GetCurrentPredictedGCD and integ:GetCurrentPredictedGCD()) or 0
  end

  -- Gap p90 over the full sample (player gap, not sys delay).
  if metrics.GetGapStatsFull then
    local gs = metrics:GetGapStatsFull()
    self.slow.gapP90 = (gs and gs.p90) or 0
  end
end

local function RecomputeDiag(self, now, metrics, diagCtx, windowSec, force)
  self.slowDiag = self.slowDiag or {}
  local d = self.slowDiag

  local refresh = self._refreshSec or 5
  local counts = metrics.GetPressClassCounts and metrics:GetPressClassCounts() or { cycles = 0, queued = 0, late = 0, none = 0 }
  local cycles = (diagCtx and diagCtx.cycles) or (counts.cycles or 0)

  -- Ensure we recompute when switching between rolling window and full-segment mode
  -- (e.g., combat -> post-combat final report), even if refresh cadence hasn't elapsed.
  local modeKey = (windowSec and windowSec > 0) and ("win" .. tostring(windowSec)) or "segment"
  if d._lastMode ~= modeKey then
    force = true
    d._lastMode = modeKey
  end

  -- Hard refresh cadence: every 5s, plus immediate first render. Allow forcing.
  if (not force) and d.analysis ~= "" and now < (d.nextUpdate or 0) and (d.lastCycles or -1) == cycles then
    return
  end
  d.nextUpdate = now + refresh
  d.lastCycles = cycles

  -- Segment-level distributions (cheap getters)
  if metrics.GetQueueLeadStats then
    local s = metrics:GetQueueLeadStats()
    d.qLeadP90 = (s and s.p90) or 0
  end

  -- Queued start delay distribution (segment-level)
  if metrics.GetStartDelayQueuedStats then
    local s = metrics:GetStartDelayQueuedStats()
    d.qDelayMed = (s and s.median) or 0
    d.qDelayP90 = (s and s.p90) or 0
  end

  if metrics.GetLatePressStats then
    local s = metrics:GetLatePressStats()
    d.lPressMed = (s and s.median) or 0
    d.lPressP90 = (s and s.p90) or 0
  end
  if metrics.GetAfterPressLateStats then
    local s = metrics:GetAfterPressLateStats()
    d.lAfterMed = (s and s.median) or 0
    d.lAfterP90 = (s and s.p90) or 0
  end

  -- HUD shares (segment-level)
  if metrics.GetQueueCoverageShare then
    local _, _, share = metrics:GetQueueCoverageShare()
    d.qcPct = share or 0
  end
  if metrics.GetAFKPressShare then
    local _, denom, share = metrics:GetAFKPressShare()
    d.afkDen = denom or 0
    d.afkPressPct = share or 0
  end
  if metrics.GetQueuedDelayNonZeroShare then
    local _, _, share = metrics:GetQueuedDelayNonZeroShare()
    d.sdqPlusPct = share or 0
  end

  d.counts = counts

  -- Failures summary (window/segment)
  local fTopCat, fTopShare, fTotal, fResShare = "OTH", 0, 0, 0
  if NS.Failures then
    local sum
    if windowSec and windowSec > 0 and NS.Failures.GetWindowSummary then
      sum = NS.Failures:GetWindowSummary(now, windowSec)
    elseif NS.Failures.GetSegmentSummary then
      sum = NS.Failures:GetSegmentSummary()
    end
    if sum then
      fTopCat = sum.topCat or fTopCat
      fTopShare = sum.topShare or fTopShare
      fTotal = sum.total or fTotal
      fResShare = sum.resShare or fResShare
    end
  end
  d.fTopCat, d.fTopShare, d.fTotal, d.fResShare = fTopCat, fTopShare, fTotal, fResShare

  -- Build analysis line (rules live inside BuildAnalysisLine()).
  local args = diagCtx or {}
  args.cycles = cycles
  args.counts = counts
  args.fTopCat = fTopCat
  args.fTopShare = fTopShare
  args.fTotal = fTotal
  args.fResShare = fResShare
  local line, tag = BuildAnalysisLine(args)
  d.analysis = line
  d.analysisTag = tag
end

function H:Update(forceFinal)
  if not self.frame or not self.lines then return end
  if not self.frame:IsShown() then return end

  local now = GetTime()
  local cfg = NS:GetConfig()
  local inCombat = UnitAffectingCombat and UnitAffectingCombat('player')
  local inSegment = NS.state and NS.state.inSegment
  local segStart = NS.state and NS.state.segmentStart
  local segElapsed = (segStart and (now - segStart)) or 0

  local metrics, integ, det = NS.Metrics, NS.Integrator, NS.GCDDetector
  if not metrics or not integ or not det then return end


  -- pull predicted gcd (also drives integrator sampling)
  local gcdPred = integ:GetCurrentPredictedGCD()

  local dur = metrics:GetFightDuration(now)
  if inCombat and segElapsed == 0 then segElapsed = dur end
  local actual = metrics:GetActualFight()

  -- piecewise integrated possible intervals
  local possibleIntervals = integ:GetPossibleFight(now)

  -- Convert to integer possible starts:
  -- starts <= floor(intervals + 1). Then enforce starts >= actual to prevent Eff>100 artifacts.
  local possibleStarts = 0
  if actual > 0 then
    possibleStarts = math.floor(possibleIntervals + 1 + 1e-6)
    if possibleStarts < actual then possibleStarts = actual end
  end

  local eff = (possibleStarts > 0) and (actual / possibleStarts) or 0
  local gcdLost = (possibleStarts > 0) and math.max(0, possibleStarts - actual) or 0

  local wastedGCD = metrics:GetWastedGCD()

  local lastReady = metrics:GetLastReadyTime()
  local tailGCD = 0
  if lastReady and lastReady < now then
    local tB = now
    if NS.state and NS.state.inSegment then
      tB = now
    elseif NS.state then
      if NS.state.segmentEndEffective and NS.state.segmentEndEffective > 0 then
        tB = NS.state.segmentEndEffective
      elseif NS.state.segmentEnd and NS.state.segmentEnd > 0 then
        tB = NS.state.segmentEnd
      end
    end
    if tB and tB > lastReady then
      tailGCD = integ:GetPossibleBetween(lastReady, tB, now)
    end
  end

  local liveStart, liveDur = det:GetLiveGCDInfo()
  local gcdNow = (liveStart and liveStart > 0 and liveDur and liveDur > 0) and liveDur or gcdPred

  local waste = metrics:GetWasteMicroTime()
  local afk = metrics:GetAFKTime()
  local lostTimeTotal = (waste + afk)

  local counts = metrics:GetPressClassCounts()
  local cycles = counts.cycles or 0
  local qHit = (cycles > 0) and ((counts.queued or 0) / cycles) or 0
  local noPressPct = (cycles > 0) and ((counts.none or 0) / cycles) or 0
  local lateShare = (cycles > 0) and ((counts.late or 0) / cycles) or 0
  qHit = Clamp01(qHit)
  noPressPct = Clamp01(noPressPct)
  lateShare = Clamp01(lateShare)

  RecomputeSlow(self, now, metrics, integ)

  -- Current open gap ("GapNow") must be computed BEFORE we build the rolling verdict context.
  -- Otherwise the verdict can see GapNow=0 while the HUD line shows a large live gap.
  local refTime = now
  if NS.state and NS.state.inSegment then
    refTime = now
  elseif NS.state then
    if NS.state.segmentEndEffective and NS.state.segmentEndEffective > 0 then
      refTime = NS.state.segmentEndEffective
    elseif NS.state.segmentEnd and NS.state.segmentEnd > 0 then
      refTime = NS.state.segmentEnd
    end
  end
  local gapNow = (NS.state and NS.state.inSegment) and metrics:GetCurrentGap(refTime) or 0

  -- Rolling context for combat: last 5 seconds. This keeps verdict responsive and prevents early-fight "sticky" states.
  local ctxWindow = nil
  if inSegment and inCombat and metrics.ComputeContext then
    ctxWindow = metrics:ComputeContext(5.0, now)
  end


  local diagCtx = self._diagCtx
  if not diagCtx then
    diagCtx = {}
    self._diagCtx = diagCtx
  end
  -- Reuse table to avoid per-tick allocations (reduces GC spikes in raids).
  if wipe then
    wipe(diagCtx)
  else
    for k in pairs(diagCtx) do diagCtx[k] = nil end
  end

  if ctxWindow then
    -- Combat verdict window: last 5 seconds
    diagCtx.inCombat = true
    diagCtx.inSegment = true
    diagCtx.elapsedSec = segElapsed
    diagCtx.idleSec = min(ctxWindow.idleSec or 0, 30)
    diagCtx.dur = ctxWindow.durSec or 0
    diagCtx.microTime = ctxWindow.microTime or 0
    diagCtx.afkTime = ctxWindow.afkTime or 0
    diagCtx.eff = ctxWindow.eff or 0
    diagCtx.possibleStarts = ctxWindow.possibleStarts or 0
    diagCtx.lostG = (ctxWindow.lostG or 0)
    diagCtx.wastedG = (ctxWindow.wastedG or 0)
    diagCtx.tailG = 0
    diagCtx.gapP90Sec = ctxWindow.gapP90Sec or 0
    diagCtx.gapNowSec = gapNow
    diagCtx.gcdNowSec = gcdNow
    diagCtx.qHit = ctxWindow.qHit or 0
    diagCtx.qCov = ctxWindow.qCov or 0
    diagCtx.qMultiShare = ctxWindow.qMultiShare or 0
    diagCtx.noPressPct = ctxWindow.noPressPct or 0
    diagCtx.lateShare = ctxWindow.lateShare or 0
    diagCtx.qDelayP90Ms = ctxWindow.qDelayP90Ms or 0
    diagCtx.lateP90Ms = ctxWindow.lateP90Ms or 0
    diagCtx.afterP90Ms = ctxWindow.afterP90Ms or 0
    diagCtx.afkDen = ctxWindow.afkDen or 0
    diagCtx.afkPressPct = ctxWindow.afkPressPct or 0
  else
    -- Post-combat (or manual stop): full segment verdict (uses effective end).
    local qMultiShare = 0
    if metrics.GetQueueMultiShare then
      local _, _, share = metrics:GetQueueMultiShare()
      qMultiShare = share or 0
    end
    local qCovShare = 0
    if metrics.GetQueueCoverageShare then
      local _, _, share = metrics:GetQueueCoverageShare()
      qCovShare = share or 0
    end
    local qDelay = metrics.GetStartDelayQueuedStats and metrics:GetStartDelayQueuedStats() or nil
    local afkPressN, afkDen, afkPressPct = 0, 0, 0
    if metrics.GetAFKPressShare then
      afkPressN, afkDen, afkPressPct = metrics:GetAFKPressShare()
    end
    local lPress = metrics.GetLatePressStats and metrics:GetLatePressStats() or nil
    local lAfter = metrics.GetAfterPressLateStats and metrics:GetAfterPressLateStats() or nil

    diagCtx.inCombat = inCombat
    diagCtx.inSegment = inSegment
    diagCtx.elapsedSec = dur
    diagCtx.idleSec = 0
    diagCtx.dur = dur
    diagCtx.microTime = waste
    diagCtx.afkTime = afk
    diagCtx.eff = eff
    diagCtx.possibleStarts = possibleStarts
    diagCtx.lostG = gcdLost
    diagCtx.wastedG = wastedGCD
    diagCtx.tailG = tailGCD
    diagCtx.gapP90Sec = (self.slow and self.slow.gapP90) or 0
    diagCtx.gapNowSec = 0
    diagCtx.gcdNowSec = gcdNow
    diagCtx.qHit = qHit
    diagCtx.qCov = qCovShare or 0
    diagCtx.qMultiShare = qMultiShare or 0
    diagCtx.noPressPct = noPressPct
    diagCtx.lateShare = lateShare
    diagCtx.qDelayP90Ms = (qDelay and qDelay.p90 or 0) * 1000
    diagCtx.lateP90Ms = (lPress and lPress.p90 or 0) * 1000
    diagCtx.afterP90Ms = (lAfter and lAfter.p90 or 0) * 1000
    diagCtx.afkDen = afkDen or 0
    diagCtx.afkPressPct = afkPressPct or 0
  end

  RecomputeDiag(self, now, metrics, diagCtx, (ctxWindow and 5.0) or nil, forceFinal)


  local sqwMs = SafeGetCVarNumber("SpellQueueWindow", 400)
  local recMs, recDiag
  if metrics and metrics.RecommendSpellQueueWindow then
    recMs, recDiag = metrics:RecommendSpellQueueWindow()
  end
  local recTag = "OK"
  if recDiag and recDiag.lowSample then
    recTag = "Low sample"
  elseif recDiag and (recDiag.multi or 0) >= (cfg.recommendMultiBadThr or 0.15) then
    recTag = "Bad management"
  elseif recDiag and (recDiag.noQueue or 0) >= (cfg.recommendSleepBadThr or 0.15) then
    recTag = "Stop sleeping!"
  end
  local recTagC = TAG_COLORS[recTag] and ColorText(TAG_COLORS[recTag], recTag) or recTag
  local sqwDisplay = string.format("%dms", math.floor(sqwMs + 0.5))
  if recMs and math.abs(sqwMs - recMs) >= (cfg.recommendDiffBadMs or 60) then
    sqwDisplay = ColorText("ff0000", sqwDisplay)
  end
  local microCapSec = (cfg.dynamicMicroCap == false) and (cfg.microCap or 0.20) or select(1, GetDynamicMicroCap(cfg))
  local microCapMs = microCapSec * 1000

  -- gapNow already computed above.

  -- Live display tweak: include the *current* open gap (GapNow) into LostT/Micro/AFK.
  -- This prevents 'LostT=0' artifacts while GapNow grows (no start yet).
  local dispWaste, dispAFK, dispLostT = waste, afk, (waste + afk)
  if NS.state and NS.state.inSegment and gapNow and gapNow > 0 then
    local cm = gapNow
    if cm > microCapSec then cm = microCapSec end
    local ca = gapNow - cm
    if ca < 0 then ca = 0 end
    dispWaste = dispWaste + cm
    dispAFK = dispAFK + ca
    dispLostT = dispWaste + dispAFK
  end

  local d = self.slowDiag
  -- Recompute analysis every 5s, but also immediately when cycle count changes.
  local currentCounts = metrics:GetPressClassCounts()
  local currentCycles = (currentCounts and currentCounts.cycles) or 0

  local qLeadP90Ms = (d.qLeadP90 or 0) * 1000
  local sdqMedMs = (d.qDelayMed or 0) * 1000
  local sdqP90Ms = (d.qDelayP90 or 0) * 1000
  local lMedMs = (d.lPressMed or 0) * 1000
  local lP90Ms = (d.lPressP90 or 0) * 1000
  local aMedMs = (d.lAfterMed or 0) * 1000
  local aP90Ms = (d.lAfterP90 or 0) * 1000
  local gapP90Ms = ((self.slow and self.slow.gapP90) or 0) * 1000
  local gapNowSec = gapNow or 0

  local cc = metrics:GetPressClassCounts()
  local cyc = (cc and cc.cycles) or 0
  local qHitShare = (cyc > 0) and (((cc and cc.queued) or 0) / cyc) or 0

  local _, _, qcPct = metrics:GetQueueCoverageShare()
  qcPct = qcPct or 0

  local _, afkDen, afkPressPct = metrics:GetAFKPressShare()
  afkDen = afkDen or 0
  afkPressPct = afkPressPct or 0

  local _, _, sdqPlusPct = metrics:GetQueuedDelayNonZeroShare()
  sdqPlusPct = sdqPlusPct or 0

  -- Color helpers for HUD values (beyond "recommendation" line).
  local function C(hex, s) return ColorText(hex, s) end

  -- Higher is worse
  local function HiBad(v, y, o, r, s)
    if v >= r then return C("ff0000", s) end
    if v >= o then return C("ff8800", s) end
    if v >= y then return C("ffff00", s) end
    return s
  end

  -- Lower is worse (for rates like efficiency or queue hit)
  local function LoBad(v, y, o, r, s)
    if v <= r then return C("ff0000", s) end
    if v <= o then return C("ff8800", s) end
    if v <= y then return C("ffff00", s) end
    return s
  end


    local effDisp = pct01(eff)
  effDisp = LoBad(eff, 0.95, 0.93, 0.90, effDisp)

  local lostGDisp = fmt1(gcdLost)
  lostGDisp = HiBad(gcdLost, 2, 4, 8, lostGDisp)

  local wstGDisp = fmt1(wastedGCD)
  wstGDisp = HiBad(wastedGCD, 2, 4, 8, wstGDisp)

  local tailGDisp = fmt1(tailGCD)
  tailGDisp = HiBad(tailGCD, 1, 2, 4, tailGDisp)

    -- =========================
  -- Render mini + (optional) details from the same snapshot
  -- =========================
  local verdictTag = (d and d.analysisTag) or "Low sample"
  self:RenderMini({
    durSec = dur,
    gcdPredMs = gcdPred and (gcdPred * 1000) or nil,
    sqwMs = sqwMs,
    recMs = recMs,
    verdictTag = verdictTag,
  })

  if self.detailsFrame and self.detailsFrame:IsShown() then
    local wastedPerMin = (dur and dur > 0) and (wastedGCD * 60 / dur) or 0
    local fTopCat = (d and d.fTopCat) or "OTH"
    local fTopShare = (d and d.fTopShare) or 0
    local fTotal = (d and d.fTotal) or 0
    local fResShare = (d and d.fResShare) or 0

    -- Details panel shows segment totals (not just the rolling verdict window),
    -- so failures don't "look empty" when you stop spamming for a few seconds.
    local segTotal, segResShare, segTopCat, segTopShare = fTotal, fResShare, fTopCat, fTopShare
    if NS.Failures and NS.Failures.GetSegmentSummary then
      local sum = NS.Failures:GetSegmentSummary()
      if sum then
        segTopCat = sum.topCat or segTopCat
        segTopShare = sum.topShare or segTopShare
        segTotal = sum.total or segTotal
        segResShare = sum.resShare or segResShare
      end
    end

    local fTopLabel = "--"

    if segTopCat and segTopCat ~= "" then
      local tok = FailTag(fTopCat)
      if tok and tok ~= "" then
        local key = "FAILTAG_" .. string.upper(tok)
        fTopLabel = NS:L(key, tok)
      else
        fTopLabel = segTopCat
      end
    end

    self:RenderDetails({
      durSec = dur,
      gcdPredMs = gcdPred and (gcdPred * 1000) or nil,
      sqwMs = sqwMs,
      recMs = recMs,
      analysisLine = d and d.analysis or nil,
      verdictTag = verdictTag,

      eff = eff,
      possible = possibleStarts,
      actual = actual,
      lostG = gcdLost,
      wastedG = wastedGCD,
      wastedPerMin = wastedPerMin,
      tailG = tailGCD,
      gapP90Ms = gapP90Ms,
      gapNowSec = gapNowSec,

      qHitShare = qHitShare,
      qLeadP90Ms = qLeadP90Ms,
      sdqPlusPct = sdqPlusPct,
      afkDen = afkDen,
      qcPct = qcPct,
      noPressPct = noPressPct,
      afkPressPct = afkPressPct,

      qDelayP90Ms = sdqP90Ms,
      sdwMedMs = sdqMedMs,
      sdwP90Ms = sdqP90Ms,

      lateMedMs = lMedMs,
      lateP90Ms = lP90Ms,
      afterMedMs = aMedMs,
      afterP90Ms = aP90Ms,

      fTotal = segTotal,
      fResShare = segResShare,
      fTopLabel = fTopLabel,
      fTopShare = segTopShare,
    })
  end
end
