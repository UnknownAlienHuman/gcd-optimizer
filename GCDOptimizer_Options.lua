-- GCDOptimizer_Options.lua
-- Settings panel: ONLY Language (auto + override).
-- Everything else is controlled via HUD context menu.

local _, NS = ...

NS.Options = NS.Options or {}
local O = NS.Options

local function SetOverride(code)
  local cfg = NS:GetConfig()
  cfg.localeOverride = code or "auto"
  if NS.HUD and NS.HUD.Update then NS.HUD:Update(true) end
end

local function GetOverride()
  local cfg = NS:GetConfig()
  return cfg.localeOverride or "auto"
end

local LANGS = {
  { code="auto", key="OPT_LANGUAGE_AUTO" },
  { code="enUS", name="English" },
  { code="ruRU", name="Русский" },
  { code="ukUA", name="Українська" },
  { code="plPL", name="Polski" },
  { code="deDE", name="Deutsch" },
  { code="frFR", name="Français" },
  { code="esES", name="Español (ES)" },
  { code="esMX", name="Español (MX)" },
  { code="itIT", name="Italiano" },
  { code="ptBR", name="Português (BR)" },
  { code="koKR", name="한국어" },
  { code="zhCN", name="简体中文" },
  { code="zhTW", name="繁體中文" },
}

local function BuildMenu(parent)
  local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  menu:SetFrameStrata("DIALOG")
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:Hide()
  menu:SetBackdrop({
    bgFile="Interface/Tooltips/UI-Tooltip-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=16,
    insets={ left=3, right=3, top=3, bottom=3 },
  })
  menu:SetBackdropColor(0,0,0,0.95)

  menu.items = {}

  local function EnsureItem(i)
    if menu.items[i] then return menu.items[i] end
    local b = CreateFrame("Button", nil, menu)
    b:SetHeight(18)
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -6 - (i-1)*18)
    b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, -6 - (i-1)*18)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(1,1,0.4) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(1,1,1) end)
    menu.items[i] = b
    return b
  end

  function menu:ShowAt(anchor)
    local override = GetOverride()
    local maxW = 180
    for i, v in ipairs(LANGS) do
      local b = EnsureItem(i)
      local label
      if v.code == "auto" then
        label = NS:L(v.key, "Auto (client)")
      else
        label = v.name or v.code
      end
      if v.code == override then label = "• " .. label end
      b.text:SetText(label)
      maxW = math.max(maxW, b.text:GetStringWidth() + 20)
      b:SetScript("OnClick", function()
        menu:Hide()
        SetOverride(v.code)
        if anchor and anchor.SetText then
          anchor:SetText(NS:L("OPT_LANGUAGE", "Language") .. ": " .. (v.code=="auto" and NS:L("OPT_LANGUAGE_AUTO","Auto") or (v.name or v.code)))
        end
      end)
    end
    menu:SetSize(maxW, 10 + #LANGS*18)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -60)
    menu:Show()
  end

  return menu
end

local function CreatePanel()
  local p = CreateFrame("Frame")
  p.name = "GCD Optimizer"

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("GCD Optimizer")

  local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  sub:SetText(NS:L("OPT_LANGUAGE", "Language"))

  local btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  btn:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
  btn:SetSize(260, 24)

  local function RefreshBtn()
    local ov = GetOverride()
    local label = (ov=="auto") and NS:L("OPT_LANGUAGE_AUTO","Auto (client)") or ov
    for _, v in ipairs(LANGS) do
      if v.code == ov and v.name then label = v.name end
    end
    local prefix = NS:L("OPT_LANGUAGE", "Language")
    if not prefix or prefix == "" then prefix = "Language" end
    local t = prefix .. ": " .. label
    btn:SetText(t)
    if btn.Text and btn.Text.SetText then btn.Text:SetText(t) end
  end

  local menu = BuildMenu(p)
  btn:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide() else menu:ShowAt(btn) end
  end)

  p:SetScript("OnShow", function() RefreshBtn() end)
  RefreshBtn() -- initial

  -- Hide menu when clicking outside.
  p:SetScript("OnMouseDown", function(_, btnName)
    if btnName == "LeftButton" and menu:IsShown() then
      local f = GetMouseFocus()
      if f ~= btn and f ~= menu then menu:Hide() end
    end
  end)

  return p
end

function O:Init()
  if self._inited then return end
  self._inited = true

  local panel = CreatePanel()

  -- Dragonflight+ Settings
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "GCD Optimizer")
    Settings.RegisterAddOnCategory(category)
    return
  end

  -- Legacy interface options
  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end
