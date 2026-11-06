-- GCDOptimizer_HUD.lua
-- Compact source-aware HUD and details panel. UI rendering consumes only
-- ordinary values produced by the detector/metrics boundary.

local _, NS = ...
local U = NS.Util

NS.HUD = NS.HUD or {}
local H = NS.HUD

local ANALYSIS_REFRESH_INTERVAL = 1.0

local TAG_COLORS = {
  ["OK"] = "33ff66",
  ["Low sample"] = "ffff55",
  ["Stop sleeping!"] = "ff3333",
  ["Bad management"] = "ff9933",
  ["Bad server!"] = "cc77ff",
  ["Press faster!"] = "ff5555",
}

local function Now()
  return GetTime()
end

local function ColorText(hex, text)
  return "|cff" .. hex .. tostring(text or "") .. "|r"
end

local function Percent(value, digits)
  local format = digits == 1 and "%.1f%%" or "%.0f%%"
  return string.format(format, (value or 0) * 100)
end

local function Milliseconds(value)
  if value == nil then return "--" end
  return string.format("%.0fms", value)
end

local function Seconds(value)
  if value == nil then return "--" end
  return string.format("%.1fs", value)
end

local function Number(value, digits)
  if value == nil then return "--" end
  return string.format(digits == 1 and "%.1f" or "%.0f", value)
end

local function SafeGetCVarNumber(name, fallback)
  local number = tonumber(GetCVar(name))
  return number or fallback
end

local function SourceLabel(source)
  if source == U.GCD_SOURCE_DIRECT then
    return NS:L("OBS_DIRECT", "exact")
  elseif source == U.GCD_SOURCE_ESTIMATED then
    return NS:L("OBS_ESTIMATED", "estimated")
  end
  return NS:L("OBS_CACHED", "cached")
end

local function ColorVerdict(tag)
  local color = TAG_COLORS[tag] or TAG_COLORS.OK
  return ColorText(color, NS:LT(tag))
end

local function FailureLabel(category)
  if category == "RES" then return NS:L("FAILTAG_RESOURCES", "resources") end
  if category == "CD" then return NS:L("FAILTAG_CD", "cooldown") end
  if category == "TGT" then return NS:L("FAILTAG_TARGET", "target") end
  if category == "RNG" then return NS:L("FAILTAG_RANGE", "range") end
  if category == "LOS" then return NS:L("FAILTAG_LOS", "line of sight") end
  if category == "MOV" then return NS:L("FAILTAG_MOVING", "moving") end
  return NS:L("FAILTAG_OTHER", "other")
end

local function BuildVerdict(snapshot)
  local lowSample = (snapshot.elapsedSec or 0) < 10
    or (snapshot.exactCycles or 0) < 5

  local tag = "OK"
  local reason = nil
  if snapshot.inCombat and (snapshot.idleSec or 0) >= 2 then
    tag = "Stop sleeping!"
    reason = string.format("%s %.1fs", NS:L("ANL_IDLE", "Idle"), snapshot.idleSec)
  elseif (snapshot.attributable or 0) >= 6
    and (snapshot.queueHit or 0) >= 0.65
    and (snapshot.lateShare or 0) < 0.25
    and (snapshot.queueDelayP90Ms or 0) >= 220
  then
    tag = "Bad server!"
    reason = string.format("%s %.0fms", NS:L("MET_SDQ_P90", "Queued-start delay p90"), snapshot.queueDelayP90Ms)
  elseif ((snapshot.exactCycles or 0) >= 5 and (snapshot.ambiguousShare or 0) >= 0.20)
    or ((snapshot.afkDen or 0) >= 3 and (snapshot.afkPressPct or 0) >= 0.45)
    or ((snapshot.failureTotal or 0) >= 3 and (snapshot.afkTime or 0) >= 0.7)
  then
    tag = "Bad management"
    if (snapshot.ambiguousShare or 0) >= 0.20 then
      reason = string.format("%s %s", NS:L("MET_AMBIGUOUS", "Ambiguous input"), Percent(snapshot.ambiguousShare))
    elseif (snapshot.afkDen or 0) >= 3 then
      reason = string.format("%s %s", NS:L("MET_AFK_PRESS", "Pressing during gaps"), Percent(snapshot.afkPressPct))
    else
      reason = string.format("%s %d", NS:L("MET_FAIL_TOTAL", "Failed attempts"), snapshot.failureTotal or 0)
    end
  elseif (snapshot.lateShare or 0) >= 0.35
    or (snapshot.gapP90Ms or 0) >= 150
    or (snapshot.wastedPerMinute or 0) >= 4
  then
    tag = "Press faster!"
    if (snapshot.lateShare or 0) >= 0.35 then
      reason = string.format("%s %s", NS:L("MET_LATE_SHARE", "Late input"), Percent(snapshot.lateShare))
    else
      reason = string.format("%s %.0fms", NS:L("MET_GAP_P90", "Gap p90"), snapshot.gapP90Ms or 0)
    end
  end

  if lowSample then
    local text = ColorVerdict("Low sample")
    if tag ~= "OK" then text = text .. " · " .. ColorVerdict(tag) end
    if reason then text = text .. " (" .. reason .. ")" end
    return "Low sample", text
  end

  local text = ColorVerdict(tag)
  if reason then text = text .. " (" .. reason .. ")" end
  return tag, text
end

local function SetBackdrop(frame, alpha)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.015, 0.02, 0.03, alpha or 0.92)
  frame:SetBackdropBorderColor(0.22, 0.55, 0.78, 0.85)
end

local function MakeDraggable(frame)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
end

function H:Init()
  if self.frame then
    self.frame:SetShown(NS:GetConfig().showHUD)
    return
  end

  local mini = CreateFrame("Frame", "GCDOptimizerHUD", UIParent, "BackdropTemplate")
  mini:SetSize(350, 100)
  mini:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
  mini:SetClampedToScreen(true)
  SetBackdrop(mini, 0.90)
  MakeDraggable(mini)
  self.frame = mini

  local close = CreateFrame("Button", nil, mini, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", mini, "TOPRIGHT", 4, 4)
  close:SetScript("OnClick", function() NS:SetHUDShown(false) end)

  local expand = CreateFrame("Button", nil, mini, "UIPanelButtonTemplate")
  expand:SetSize(24, 20)
  expand:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, -2)
  expand:SetText(">")
  expand:SetScript("OnClick", function() self:SetDetailsShown(not self.detailsFrame:IsShown()) end)
  self.expandButton = expand

  self.lines = {}
  for index = 1, 4 do
    local template = index == 4 and "GameFontNormal" or "GameFontHighlightSmall"
    local line = mini:CreateFontString(nil, "OVERLAY", template)
    line:SetPoint("TOPLEFT", mini, "TOPLEFT", 12, -12 - ((index - 1) * 20))
    line:SetPoint("RIGHT", mini, "RIGHT", -12, 0)
    line:SetJustifyH("LEFT")
    self.lines[index] = line
  end

  local details = CreateFrame("Frame", "GCDOptimizerDetails", UIParent, "BackdropTemplate")
  details:SetSize(580, 430)
  details:SetPoint("TOP", mini, "BOTTOM", 0, -8)
  details:SetClampedToScreen(true)
  SetBackdrop(details, 0.96)
  MakeDraggable(details)
  details:Hide()
  self.detailsFrame = details

  local detailsClose = CreateFrame("Button", nil, details, "UIPanelCloseButton")
  detailsClose:SetPoint("TOPRIGHT", details, "TOPRIGHT", 4, 4)
  detailsClose:SetScript("OnClick", function() self:SetDetailsShown(false) end)

  local title = details:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", details, "TOPLEFT", 12, -10)
  title:SetText("GCD Optimizer")

  local scroll = CreateFrame("ScrollFrame", nil, details, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", details, "TOPLEFT", 12, -38)
  scroll:SetPoint("BOTTOMRIGHT", details, "BOTTOMRIGHT", -30, 12)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(530, 1)
  scroll:SetScrollChild(content)
  self.detailsContent = content
  self.detailRows = {}

  local function MouseDown(_, button)
    if button == "RightButton" then self:ShowContextMenu() end
  end
  mini:SetScript("OnMouseDown", MouseDown)
  details:SetScript("OnMouseDown", MouseDown)

  local combatFrame = CreateFrame("Frame")
  combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  combatFrame:SetScript("OnEvent", function()
    if self.sqwPopup then self.sqwPopup:Hide() end
  end)
  self.combatFrame = combatFrame

  mini:SetShown(NS:GetConfig().showHUD)
  self:Update(true)
end

function H:SetDetailsShown(shown)
  if not self.detailsFrame then return end
  shown = shown and self.frame and self.frame:IsShown() or false
  self.detailsFrame:SetShown(shown)
  if self.expandButton then self.expandButton:SetText(shown and "<" or ">") end
  if shown then self:Update(true) end
end

function H:EnsureMenu()
  if self.contextMenu then return self.contextMenu end

  local menu = CreateFrame("Frame", "GCDOptimizerContextMenu", UIParent, "BackdropTemplate")
  menu:SetFrameStrata("DIALOG")
  menu:SetClampedToScreen(true)
  menu:SetSize(220, 170)
  SetBackdrop(menu, 0.98)
  menu.buttons = {}
  menu:Hide()

  local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -10)
  title:SetText("GCD Optimizer")

  for index = 1, 6 do
    local button = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    button:SetSize(196, 22)
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -30 - ((index - 1) * 23))
    menu.buttons[index] = button
  end
  self.contextMenu = menu
  return menu
end

function H:ShowContextMenu()
  local menu = self:EnsureMenu()
  local running = NS.state and NS.state.inSegment
  local detailsShown = self.detailsFrame and self.detailsFrame:IsShown()
  local actions = {
    {
      text = running and NS:L("MENU_STOP", "Stop") or NS:L("MENU_START", "Start"),
      action = function()
        NS.state.autoCombat = false
        if running then NS:PauseSegment(Now()) else NS:StartSegment(Now()) end
      end,
    },
    {
      text = NS:L("MENU_RESET", "Reset"),
      action = function() NS:ResetAndContinue(Now()) end,
    },
    {
      text = detailsShown and NS:L("MENU_COLLAPSE", "Collapse") or NS:L("MENU_EXPAND", "Expand"),
      action = function() self:SetDetailsShown(not detailsShown) end,
    },
    {
      text = NS:L("MENU_SET_SQW", "Set SQW"),
      action = function() self:ShowSetSQW() end,
    },
    {
      text = NS:L("MENU_HIDE", "Hide"),
      action = function() NS:SetHUDShown(false) end,
    },
    {
      text = NS:L("OPT_CLOSE", "Close"),
      action = function() menu:Hide() end,
    },
  }

  for index, item in ipairs(actions) do
    local button = menu.buttons[index]
    local action = item.action
    button:SetText(item.text)
    button:SetScript("OnClick", function()
      menu:Hide()
      action()
      self:Update(true)
    end)
  end

  local scale = UIParent:GetEffectiveScale() or 1
  local x, y = GetCursorPosition()
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x / scale) + 2, (y / scale) - 2)
  menu:Show()
end

function H:ShowSetSQW()
  if InCombatLockdown and InCombatLockdown() then
    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGCDOpt|r " .. NS:L("SQW_COMBAT", "SpellQueueWindow cannot be changed in combat."))
    end
    return
  end

  local popup = self.sqwPopup
  if not popup then
    popup = CreateFrame("Frame", "GCDOptimizerSQWPopup", UIParent, "BackdropTemplate")
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetSize(290, 135)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    SetBackdrop(popup, 0.98)

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -12)
    title:SetText(NS:L("SQW_TITLE", "Set Spell Queue Window"))

    local prompt = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    prompt:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    prompt:SetText(NS:L("SQW_PROMPT", "Value (ms):"))

    local edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    edit:SetSize(90, 22)
    edit:SetPoint("TOPLEFT", prompt, "BOTTOMLEFT", 0, -6)
    edit:SetNumeric(true)
    edit:SetAutoFocus(true)
    popup.edit = edit

    local status = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    status:SetPoint("RIGHT", popup, "RIGHT", -10, 0)
    status:SetJustifyH("LEFT")
    popup.status = status

    local apply = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    apply:SetSize(100, 24)
    apply:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 12, 12)
    apply:SetText(NS:L("OPT_APPLY", "Apply"))

    local cancel = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancel:SetSize(100, 24)
    cancel:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 12)
    cancel:SetText(NS:L("OPT_CLOSE", "Close"))
    cancel:SetScript("OnClick", function() popup:Hide() end)

    local function Apply()
      if InCombatLockdown and InCombatLockdown() then
        status:SetText(ColorText("ff5555", NS:L("SQW_COMBAT", "Unavailable in combat")))
        return
      end

      local value = tonumber(edit:GetText() or "")
      if not value or value < 0 or value > 4000 then
        status:SetText(ColorText("ff5555", NS:L("SQW_BAD_NUMBER", "Bad number")))
        return
      end

      value = math.floor(value + 0.5)
      -- pcall is error containment only; the explicit combat guard is the policy.
      local ok = pcall(SetCVar, "SpellQueueWindow", tostring(value))
      local current = SafeGetCVarNumber("SpellQueueWindow", -1)
      if ok and current >= 0 and math.abs(current - value) <= 1 then
        popup:Hide()
        self:Update(true)
      else
        status:SetText(ColorText("ffcc55", NS:L("SQW_SET_FAILED", "Setting was not applied")))
      end
    end

    apply:SetScript("OnClick", Apply)
    edit:SetScript("OnEnterPressed", Apply)
    edit:SetScript("OnEscapePressed", function() popup:Hide() end)
    self.sqwPopup = popup
  end

  popup.status:SetText("")
  popup.edit:SetText(tostring(SafeGetCVarNumber("SpellQueueWindow", 400)))
  popup:Show()
  popup.edit:SetFocus()
  popup.edit:HighlightText()
end

function H:EnsureDetailRow(index)
  local row = self.detailRows[index]
  if row then return row end

  row = CreateFrame("Frame", nil, self.detailsContent)
  row:SetHeight(18)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.label:SetWidth(310)
  row.label:SetJustifyH("LEFT")
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.value:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
  row.value:SetJustifyH("LEFT")
  row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.header:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.header:Hide()
  self.detailRows[index] = row
  return row
end

function H:RenderDetails(snapshot)
  if not (self.detailsFrame and self.detailsFrame:IsShown()) then return end

  local entries = {}
  local function Header(text) entries[#entries + 1] = { header = text } end
  local function Value(label, value) entries[#entries + 1] = { label = label, value = value } end

  Header(NS:L("SEC_SUMMARY", "Summary"))
  Value(NS:L("MET_TIME", "Time"), Seconds(snapshot.duration))
  Value(NS:L("HUD_GCD", "GCD"), Milliseconds(snapshot.gcdMs) .. " · " .. SourceLabel(snapshot.source))
  Value(NS:L("HUD_SQW", "Spell Queue Window"), Milliseconds(snapshot.sqwMs))
  Value(NS:L("HUD_REC_SQW", "Recommended SQW"), snapshot.recommendedMs and Milliseconds(snapshot.recommendedMs) or "--")
  Value(NS:L("HUD_VERDICT", "Verdict"), snapshot.analysisText)

  Header(NS:L("SEC_OBSERVATION", "Observation quality"))
  Value(NS:L("MET_OBS_TOTAL", "Observed starts"), Number(snapshot.observedTotal))
  Value(NS:L("MET_OBS_DIRECT", "Exact starts"), Number(snapshot.directStarts))
  Value(NS:L("MET_OBS_ESTIMATED", "Estimated starts"), Number(snapshot.estimatedStarts))
  Value(NS:L("MET_EXACT_CYCLES", "Exact cycles"), Number(snapshot.exactCycles))
  Value(NS:L("MET_ATTRIBUTABLE", "Attributable cycles"), Number(snapshot.attributable))
  Value(NS:L("MET_AMBIGUOUS", "Ambiguous cycles"), Number(snapshot.ambiguous))
  Value(NS:L("MET_UNOBSERVED", "Unobserved input"), Number(snapshot.unobserved))

  Header(NS:L("SEC_LOSSES", "Cadence"))
  Value(NS:L("MET_EFF", "Efficiency"), Percent(snapshot.efficiency, 1))
  Value(NS:L("MET_POSSIBLE", "Possible GCDs"), Number(snapshot.possible))
  Value(NS:L("MET_ACTUAL", "Observed GCDs"), Number(snapshot.actual))
  Value(NS:L("MET_LOST", "Lost GCDs"), Number(snapshot.lost))
  Value(NS:L("MET_WASTED", "Wasted GCDs"), Number(snapshot.wasted, 1))
  Value(NS:L("MET_GAP_P90", "Gap p90"), Milliseconds(snapshot.gapP90Ms))
  Value(NS:L("MET_GAP_NOW", "Current gap"), Seconds(snapshot.gapNow))

  Header(NS:L("SEC_INPUT", "Queue & input"))
  Value(NS:L("MET_QHIT", "Queue hits"), Percent(snapshot.queueHit))
  Value(NS:L("MET_QCOV", "Queue coverage"), Percent(snapshot.queueCoverage))
  Value(NS:L("MET_QUEUE_LEAD_P90", "Queue lead p90"), Milliseconds(snapshot.queueLeadP90Ms))
  Value(NS:L("MET_LATE_SHARE", "Late input"), Percent(snapshot.lateShare))
  Value(NS:L("MET_LATE_P90", "Late press p90"), Milliseconds(snapshot.lateP90Ms))
  Value(NS:L("MET_SDQ_P90", "Queued-start delay p90"), Milliseconds(snapshot.queueDelayP90Ms))
  Value(NS:L("MET_AFK_PRESS", "Pressing during gaps"), Percent(snapshot.afkPressPct))

  Header(NS:L("SEC_FAILS", "Failures"))
  Value(NS:L("MET_FAIL_TOTAL", "Failed attempts"), Number(snapshot.failureTotal))
  Value(NS:L("MET_FAIL_TOP", "Top category"), FailureLabel(snapshot.failureTop))
  Value(NS:L("MET_FAIL_TOP_SHARE", "Top share"), Percent(snapshot.failureTopShare))

  local y = 0
  for index, entry in ipairs(entries) do
    local row = self:EnsureDetailRow(index)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.detailsContent, "TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", self.detailsContent, "RIGHT", 0, 0)
    row:Show()
    row.header:Hide()
    row.label:Hide()
    row.value:Hide()

    if entry.header then
      row:SetHeight(22)
      row.header:SetText(entry.header)
      row.header:Show()
      y = y + 24
    else
      row:SetHeight(18)
      row.label:SetText(entry.label)
      row.value:SetText(entry.value)
      row.label:Show()
      row.value:Show()
      y = y + 18
    end
  end
  for index = #entries + 1, #self.detailRows do self.detailRows[index]:Hide() end
  self.detailsContent:SetHeight(math.max(1, y + 10))
end

function H:FitMiniWidth()
  if not (self.frame and self.lines) then return end
  local widest = 0
  for index = 1, #self.lines do
    local line = self.lines[index]
    if line and line.GetStringWidth then
      widest = math.max(widest, line:GetStringWidth() or 0)
    end
  end
  self.frame:SetWidth(U.Clamp(math.floor(widest + 92 + 0.5), 350, 620))
end

function H:RenderMini(snapshot)
  if not self.lines then return end
  self.lines[1]:SetText(string.format(
    "%s: %s  |  %s: %s (%s)",
    NS:L("MET_TIME", "Time"), Seconds(snapshot.duration),
    NS:L("HUD_GCD", "GCD"), Milliseconds(snapshot.gcdMs), SourceLabel(snapshot.source)
  ))
  self.lines[2]:SetText(string.format(
    "%s: %s  |  %s: %s",
    NS:L("HUD_SQW", "SQW"), Milliseconds(snapshot.sqwMs),
    NS:L("HUD_REC_SQW", "Recommended"), snapshot.recommendedMs and Milliseconds(snapshot.recommendedMs) or "--"
  ))
  self.lines[3]:SetText(string.format(
    "%s: %s  |  %s: %d/%d",
    NS:L("MET_EFF", "Efficiency"), Percent(snapshot.efficiency, 1),
    NS:L("MET_ATTRIBUTABLE", "Attributable"), snapshot.attributable or 0, snapshot.exactCycles or 0
  ))
  self.lines[4]:SetText(string.format("%s: %s", NS:L("HUD_VERDICT", "Verdict"), snapshot.analysisText))
  self:FitMiniWidth()
end

function H:CollectAnalysis(now, inSegment, inCombat)
  local metrics = NS.Metrics
  local contextWindow = inSegment and inCombat and 5.0 or nil
  local context = metrics:ComputeContext(contextWindow, now)
  local classes = metrics:GetPressClassCounts()
  local observations = metrics:GetObservationCounts()
  local gapStats = metrics:GetGapStatsFull()
  local leadStats = metrics:GetQueueLeadStats()
  local lateStats = metrics:GetLatePressStats()
  local queueDelayStats = metrics:GetStartDelayQueuedStats()
  local _, _, queueCoverage = metrics:GetQueueCoverageShare()
  local _, afkDen, afkPressPct = metrics:GetAFKPressShare()

  local recommendation, recommendationInfo = metrics:RecommendSpellQueueWindow()
  if recommendationInfo.lowSample then recommendation = nil end

  local failure = { total = 0, topCat = "OTH", topShare = 0 }
  if NS.Failures then
    if contextWindow and NS.Failures.GetWindowSummary then
      failure = NS.Failures:GetWindowSummary(now, contextWindow) or failure
    elseif NS.Failures.GetSegmentSummary then
      failure = NS.Failures:GetSegmentSummary() or failure
    end
  end

  return {
    inSegment = inSegment,
    inCombat = inCombat,
    recommendedMs = recommendation,
    gapP90Ms = (context.gapP90Sec or gapStats.p90 or 0) * 1000,
    queueHit = context.qHit or 0,
    queueCoverage = context.qCov or queueCoverage or 0,
    queueLeadP90Ms = (leadStats.p90 or 0) * 1000,
    queueDelayP90Ms = context.qDelayP90Ms or ((queueDelayStats.p90 or 0) * 1000),
    lateShare = context.lateShare or 0,
    lateP90Ms = context.lateP90Ms or ((lateStats.p90 or 0) * 1000),
    afkTime = context.afkTime or 0,
    afkDen = context.afkDen or afkDen or 0,
    afkPressPct = context.afkPressPct or afkPressPct or 0,
    observedTotal = observations.total or 0,
    directStarts = observations.direct or 0,
    estimatedStarts = observations.estimated or 0,
    exactCycles = observations.exactCycles or 0,
    attributable = observations.attributable or 0,
    ambiguous = observations.ambiguous or 0,
    unobserved = observations.unobserved or 0,
    ambiguousShare = (classes.cycles or 0) > 0
      and ((classes.ambiguous or 0) / classes.cycles) or 0,
    failureTotal = failure.total or 0,
    failureTop = failure.topCat or "OTH",
    failureTopShare = failure.topShare or 0,
  }
end

function H:GetAnalysis(now, inSegment, inCombat, force)
  local cache = self.analysisCache
  local stateChanged = cache
    and (cache.inSegment ~= inSegment or cache.inCombat ~= inCombat)
  if force or not cache or stateChanged or now >= (self.nextAnalysisAt or 0) then
    cache = self:CollectAnalysis(now, inSegment, inCombat)
    self.analysisCache = cache
    self.nextAnalysisAt = now + ANALYSIS_REFRESH_INTERVAL
  end
  return cache
end

function H:Update(force)
  if not (self.frame and self.frame:IsShown()) then return end
  local metrics = NS.Metrics
  local integrator = NS.Integrator
  if not (metrics and integrator and NS.GCDDetector) then return end

  local now = Now()
  local inSegment = NS.state and NS.state.inSegment or false
  local inCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false
  local duration = metrics:GetFightDuration(now)
  local predicted, predictionSource = integrator:GetCurrentPrediction()
  local _, liveDuration, liveSource = NS.GCDDetector:GetLiveGCDInfo()
  local gcdDuration = liveDuration or predicted
  local source = liveDuration and liveSource or predictionSource

  local actual = metrics:GetActualFight()
  local possibleIntervals = integrator:GetPossibleFight(now)
  local possible = actual > 0 and math.floor(possibleIntervals + 1 + 1e-6) or 0
  if possible < actual then possible = actual end
  local efficiency = possible > 0 and (actual / possible) or 0
  local lost = math.max(0, possible - actual)
  local analysis = self:GetAnalysis(now, inSegment, inCombat, force)

  local wasted = metrics:GetWastedGCD()
  local idle = metrics:GetSecondsSinceLastPress(now)
  local snapshot = {
    duration = duration,
    elapsedSec = duration,
    inCombat = inCombat,
    source = source,
    gcdMs = gcdDuration and (gcdDuration * 1000) or nil,
    sqwMs = SafeGetCVarNumber("SpellQueueWindow", 400),
    recommendedMs = analysis.recommendedMs,
    actual = actual,
    possible = possible,
    efficiency = efficiency,
    lost = lost,
    wasted = wasted,
    wastedPerMinute = duration > 0 and (wasted * 60 / duration) or 0,
    gapP90Ms = analysis.gapP90Ms,
    gapNow = inSegment and metrics:GetCurrentGap(now) or 0,
    queueHit = analysis.queueHit,
    queueCoverage = analysis.queueCoverage,
    queueLeadP90Ms = analysis.queueLeadP90Ms,
    queueDelayP90Ms = analysis.queueDelayP90Ms,
    lateShare = analysis.lateShare,
    lateP90Ms = analysis.lateP90Ms,
    afkTime = analysis.afkTime,
    afkDen = analysis.afkDen,
    afkPressPct = analysis.afkPressPct,
    idleSec = idle and math.min(idle, 999) or nil,
    observedTotal = analysis.observedTotal,
    directStarts = analysis.directStarts,
    estimatedStarts = analysis.estimatedStarts,
    exactCycles = analysis.exactCycles,
    attributable = analysis.attributable,
    ambiguous = analysis.ambiguous,
    unobserved = analysis.unobserved,
    ambiguousShare = analysis.ambiguousShare,
    failureTotal = analysis.failureTotal,
    failureTop = analysis.failureTop,
    failureTopShare = analysis.failureTopShare,
  }

  snapshot.verdictTag, snapshot.analysisText = BuildVerdict(snapshot)
  self.lastSnapshot = snapshot
  self:RenderMini(snapshot)
  self:RenderDetails(snapshot)
end

function H:StartTicker()
  if self.ticker then self.ticker:Cancel(); self.ticker = nil end
  if not (self.frame and self.frame:IsShown()) then return end
  if not (NS.state and NS.state.inSegment) then
    self:Update(true)
    return
  end

  local interval = U.Clamp(NS:GetConfig().hudUpdateInterval or 0.25, 0.10, 1.00)
  self.ticker = C_Timer.NewTicker(interval, function() self:Update(false) end)
end

function H:StopTicker()
  if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

function H:OnSegmentStart()
  self:StartTicker()
  self:Update(true)
end

function H:OnSegmentEnd()
  self:StopTicker()
  self:Update(true)
end

function H:OnGCDStart()
  self:Update(true)
end

function H:OnRateUpdate()
  self:Update(false)
end
