-- GCDOptimizer_Options.lua
-- Settings panel: language override only. Runtime controls remain in the HUD
-- context menu, minimap launcher, and /gcdopt command surface.

local _, NS = ...

NS.Options = NS.Options or {}
local O = NS.Options

local LANGUAGES = {
  { code = "auto", key = "OPT_LANGUAGE_AUTO" },
  { code = "enUS", name = "English" },
  { code = "ruRU", name = "Русский" },
  { code = "ukUA", name = "Українська" },
  { code = "plPL", name = "Polski" },
  { code = "deDE", name = "Deutsch" },
  { code = "frFR", name = "Français" },
  { code = "esES", name = "Español (ES)" },
  { code = "esMX", name = "Español (MX)" },
  { code = "itIT", name = "Italiano" },
  { code = "ptBR", name = "Português (BR)" },
  { code = "koKR", name = "한국어" },
  { code = "zhCN", name = "简体中文" },
  { code = "zhTW", name = "繁體中文" },
}

local function SetOverride(code)
  local cfg = NS:GetConfig()
  cfg.localeOverride = code or "auto"
  if NS.HUD and NS.HUD.Update then NS.HUD:Update(true) end
end

local function GetOverride()
  return NS:GetConfig().localeOverride or "auto"
end

local function LanguageName(code)
  if code == "auto" then
    return NS:L("OPT_LANGUAGE_AUTO", "Auto (client)")
  end
  for _, language in ipairs(LANGUAGES) do
    if language.code == code then return language.name or code end
  end
  return code
end

local function BuildMenu(parent)
  local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  menu:SetFrameStrata("DIALOG")
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:Hide()
  menu:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  menu:SetBackdropColor(0, 0, 0, 0.95)
  menu.items = {}

  local function EnsureItem(index)
    if menu.items[index] then return menu.items[index] end

    local button = CreateFrame("Button", nil, menu)
    button:SetHeight(18)
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -6 - (index - 1) * 18)
    button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, -6 - (index - 1) * 18)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("LEFT", button, "LEFT", 0, 0)
    button.text:SetJustifyH("LEFT")
    button:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 0.4) end)
    button:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)
    menu.items[index] = button
    return button
  end

  function menu:ShowAt(anchor)
    local selected = GetOverride()
    local maxWidth = 180

    for index, language in ipairs(LANGUAGES) do
      local button = EnsureItem(index)
      local label = LanguageName(language.code)
      if language.code == selected then label = "• " .. label end
      button.text:SetText(label)
      maxWidth = math.max(maxWidth, button.text:GetStringWidth() + 20)
      button:SetScript("OnClick", function()
        menu:Hide()
        SetOverride(language.code)
        if anchor and anchor.SetText then
          anchor:SetText(NS:L("OPT_LANGUAGE", "Language") .. ": " .. LanguageName(language.code))
        end
      end)
    end

    menu:SetSize(maxWidth, 10 + #LANGUAGES * 18)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -60)
    menu:Show()
  end

  return menu
end

local function CreatePanel()
  local panel = CreateFrame("Frame")
  panel.name = "GCD Optimizer"

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("GCD Optimizer")

  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetText(NS:L("OPT_LANGUAGE", "Language"))

  local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  button:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
  button:SetSize(260, 24)

  local menu = BuildMenu(panel)
  local function RefreshButton()
    button:SetText(NS:L("OPT_LANGUAGE", "Language") .. ": " .. LanguageName(GetOverride()))
  end

  button:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide() else menu:ShowAt(button) end
  end)
  panel:SetScript("OnShow", RefreshButton)
  panel:SetScript("OnHide", function() menu:Hide() end)
  RefreshButton()

  return panel
end

function O:Init()
  if self._inited then return end
  self._inited = true

  local panel = CreatePanel()
  self.panel = panel

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "GCD Optimizer")
    Settings.RegisterAddOnCategory(category)
    self.category = category
    return
  end

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end
