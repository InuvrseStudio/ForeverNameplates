-- Options panels (Esc > Options > AddOns > InvurseUI, or /iui).

local ADDON, ns = ...

local COLOR_ROWS = {
    { key = "safe",    label = "Safe",    desc = "Tank: you have aggro" },
    { key = "warning", label = "Warning", desc = "Aggro is about to change hands" },
    { key = "danger",  label = "Danger",  desc = "Tank: someone else has aggro  |  DPS: you pulled it" },
}

local TEXTURE_AREAS = {
    { key = "unitFrames",  label = "Player, target and party frames (health and mana)" },
    { key = "raidFrames",  label = "Raid frames" },
    { key = "damageMeter", label = "Damage meter" },
    { key = "nameplates",  label = "Nameplate health bars" },
}

local mainPanel, category
local widgets = {}

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function Header(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Note(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Checkbox(parent, text, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(26, 26)
    local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    label:SetText(text)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked()) end)
    return cb
end

local function Slider(parent, text, x, y, minV, maxV, step, onChange)
    local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    s:SetPoint("TOPLEFT", x, y - 18)
    s:SetSize(220, 17)
    s:SetOrientation("HORIZONTAL")
    s:SetHitRectInsets(0, 0, -6, -6)
    if s.SetBackdrop then
        s:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
    end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)

    local label = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    label:SetText(text)

    local value = s:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)
    s.valueText = value

    local low = s:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, -1)
    low:SetFormattedText("%d%%", minV * 100)
    local high = s:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, -1)
    high:SetFormattedText("%d%%", maxV * 100)

    s:SetScript("OnValueChanged", function(self, v, userInput)
        v = math.floor(v / step + 0.5) * step
        self.valueText:SetFormattedText("%d%%", v * 100 + 0.5)
        if userInput then onChange(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        local v = math.min(maxV, math.max(minV, self:GetValue() + delta * step))
        self:SetValue(v)
        onChange(v)
    end)
    return s
end

local function OpenColorPicker(color, onChange)
    local r, g, b = color[1], color[2], color[3]
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onChange(nr, ng, nb)
    end
    local function cancel()
        onChange(r, g, b)
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = apply,
            cancelFunc = cancel,
        })
    else
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = apply
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame.previousValues = { r, g, b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ShowUIPanel(ColorPickerFrame)
    end
end

local function ColorSwatch(parent, row, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(22, 22)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.8, 0.8, 0.8, 1)
    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.swatch = swatch

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)

    local label = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    label:SetText(row.label)
    local desc = btn:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("LEFT", label, "RIGHT", 8, 0)
    desc:SetText(row.desc)

    btn:SetScript("OnClick", function()
        OpenColorPicker(ns.db.threat.colors[row.key], function(r, g, b)
            local c = ns.db.threat.colors[row.key]
            c[1], c[2], c[3] = r, g, b
            ns.Refresh()
        end)
    end)
    return btn
end

-- A small bar on a dark background with a thin black border, roughly like the stock plate.
local function PreviewBar(parent, x, y, width, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetPoint("TOPLEFT", x, y)
    bar:SetSize(width or 120, 12)
    bar:SetFrameLevel(parent:GetFrameLevel() + 5)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(r or 0.75, g or 0.05, b or 0.05)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.6)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 1)

    local border = CreateFrame("Frame", nil, bar)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(bar:GetFrameLevel() - 1)
    local bt = border:CreateTexture(nil, "BACKGROUND")
    bt:SetAllPoints()
    bt:SetColorTexture(0, 0, 0, 1)
    bar.border = border
    return bar
end

local function ResetButton(parent, section, y)
    local reset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    reset:SetPoint("TOPLEFT", 16, y)
    reset:SetSize(140, 24)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function()
        ns.ResetSettings(section)
        ns.Refresh()
    end)
    return reset
end

local function Page(name, title, subtitle)
    local page = CreateFrame("Frame")
    page.name = name
    page:SetScript("OnShow", function() ns.RefreshOptions() end)

    local fs = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 16, -16)
    fs:SetText(title)
    local sub = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -6)
    sub:SetText(subtitle)
    return page
end

local function Set(section, key, value)
    ns.db[section][key] = value
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local function CreateMainPage()
    local page = Page("InvurseUI", "InvurseUI", "Subtle tweaks to the stock Blizzard UI.")

    local lines = {
        { "Nameplates", "Threat glow around enemy nameplates, and the level shown beside the name." },
        { "Textures",   "Flat bar textures for the unit frames, raid frames, damage meter and nameplates." },
        { "Fonts",      "Change the font used across the standard UI." },
    }
    for i, line in ipairs(lines) do
        local y = -64 - (i - 1) * 40
        Header(page, line[1], 16, y)
        Note(page, line[2], 16, y - 16)
    end
    Note(page, "Pick a section in the list on the left.  Type /iui to open this panel.", 16, -200)

    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetPoint("TOPLEFT", 16, -230)
    reset:SetSize(160, 24)
    reset:SetText("Reset all settings")
    reset:SetScript("OnClick", function()
        ns.ResetSettings()
        ns.Refresh()
    end)
    return page
end

local function CreateNameplatesPage()
    local page = Page("Nameplates", "Nameplates", "Threat glow around the stock nameplates.")

    widgets.levelBesideName = Checkbox(page, "Show the level beside the name  (16 - Forest Spider)", 16, -60,
        function(on) Set("nameplates", "levelBesideName", on) end)
    widgets.enabled = Checkbox(page, "Enable threat glow", 16, -86,
        function(on) Set("threat", "enabled", on) end)

    Header(page, "Threat mode", 16, -126)
    widgets.tank = Checkbox(page, "Tank  (show who has aggro on every mob)", 16, -144,
        function() Set("threat", "mode", "tank") end)
    widgets.dps = Checkbox(page, "DPS / Healer  (only warn when you're pulling aggro)", 16, -170,
        function() Set("threat", "mode", "dps") end)

    Header(page, "Glow", 16, -212)
    widgets.size = Slider(page, "Glow thickness", 20, -232, ns.SIZE_MIN, ns.SIZE_MAX, 0.05,
        function(v) Set("threat", "size", v) end)
    widgets.alpha = Slider(page, "Glow opacity", 20, -288, ns.ALPHA_MIN, ns.ALPHA_MAX, 0.05,
        function(v) Set("threat", "alpha", v) end)

    Header(page, "Colors", 16, -346)
    for i, row in ipairs(COLOR_ROWS) do
        widgets[row.key] = ColorSwatch(page, row, 20, -368 - (i - 1) * 30)
    end

    Header(page, "Preview", 300, -212)
    widgets.preview = {}
    for i, row in ipairs(COLOR_ROWS) do
        local y = -242 - (i - 1) * 38
        local bar = PreviewBar(page, 310, y)
        bar.glow = ns.CreateGlow(page, bar.border)
        bar.glow:SetFrameLevel(math.max(0, bar.border:GetFrameLevel() - 1))
        widgets.preview[row.key] = bar
        local label = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", 440, y)
        label:SetText(row.label)
    end

    ResetButton(page, "threat", -474)
    return page
end

local function CreateTexturesPage()
    local page = Page("Textures", "Textures", "Flat status bar textures across the UI.")

    Header(page, "Bar texture", 16, -60)
    widgets.styles = {}
    for i, style in ipairs(ns.TEXTURE_STYLES) do
        local y = -78 - (i - 1) * 26
        widgets.styles[style.key] = Checkbox(page, style.label, 16, y,
            function() Set("textures", "style", style.key) end)
        local bar = PreviewBar(page, 200, y - 7, 140, 0.1, 0.8, 0.1)
        bar:SetStatusBarTexture(style.path or "Interface\\TargetingFrame\\UI-StatusBar")
        local mana = PreviewBar(page, 352, y - 7, 140, 0.0, 0.35, 1.0)
        mana:SetStatusBarTexture(style.path or "Interface\\TargetingFrame\\UI-StatusBar")
        mana:SetValue(0.8)
    end

    Header(page, "Health bar color  (player, target and party frames)", 16, -172)
    widgets.healthColors = {}
    for i, option in ipairs(ns.HEALTH_COLORS) do
        widgets.healthColors[option.key] = Checkbox(page, option.label, 16, -190 - (i - 1) * 26,
            function() Set("textures", "healthColor", option.key) end)
    end

    Header(page, "Apply to", 16, -258)
    widgets.areas = {}
    for i, area in ipairs(TEXTURE_AREAS) do
        widgets.areas[area.key] = Checkbox(page, area.label, 16, -276 - (i - 1) * 26,
            function(on) Set("textures", area.key, on) end)
    end

    Note(page, "Switching an area back to Blizzard's textures asks for a UI reload.", 16, -388)
    ResetButton(page, "textures", -416)
    return page
end

local function CreateFontsPage()
    local page = Page("Fonts", "Fonts", "Change the font used across the standard UI.")

    Header(page, "UI font", 16, -60)
    local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 16, -80)
    dropdown:SetWidth(240)
    dropdown:SetupMenu(function(_, root)
        for _, font in ipairs(ns.GetFontList()) do
            root:CreateRadio(font.label,
                function() return ns.db.fonts.face == font.key end,
                function() Set("fonts", "face", font.key) end)
        end
    end)
    widgets.fontDropdown = dropdown

    Header(page, "Preview", 16, -130)
    local samples = {
        { "GameFontNormalLarge", "The quick brown fox jumps over the lazy dog" },
        { "GameFontHighlight",   "Defias Conjurer casts Frostbolt.  1234567890" },
        { "GameFontNormalSmall", "Level 16 Elite  -  Deadmines" },
    }
    for i, sample in ipairs(samples) do
        local fs = page:CreateFontString(nil, "ARTWORK", sample[1])
        fs:SetPoint("TOPLEFT", 16, -152 - (i - 1) * 24)
        fs:SetText(sample[2])
    end

    Note(page, "Fonts from LibSharedMedia (installed by other addons) are listed too.\n"
        .. "Floating combat text picks up the new font after you log out and back in.", 16, -236)
    ResetButton(page, "fonts", -276)
    return page
end

---------------------------------------------------------------------------
-- Refresh / registration
---------------------------------------------------------------------------

function ns.RefreshOptions()
    if not mainPanel then return end
    local db = ns.db
    local threat = db.threat

    widgets.levelBesideName:SetChecked(db.nameplates.levelBesideName)
    widgets.enabled:SetChecked(threat.enabled)
    widgets.tank:SetChecked(threat.mode == "tank")
    widgets.dps:SetChecked(threat.mode == "dps")
    widgets.size:SetValue(threat.size)
    widgets.alpha:SetValue(threat.alpha)
    for _, row in ipairs(COLOR_ROWS) do
        local c = threat.colors[row.key]
        widgets[row.key].swatch:SetColorTexture(c[1], c[2], c[3], 1)
        local bar = widgets.preview[row.key]
        ns.LayoutGlow(bar.glow)
        ns.ColorGlow(bar.glow, c)
        bar.glow:SetShown(threat.enabled)
    end

    for key, cb in pairs(widgets.styles) do cb:SetChecked(db.textures.style == key) end
    for key, cb in pairs(widgets.areas) do cb:SetChecked(db.textures[key]) end
    for key, cb in pairs(widgets.healthColors) do cb:SetChecked(db.textures.healthColor == key) end

    widgets.fontDropdown:GenerateMenu()
end

ns.OnInit(function()
    mainPanel = CreateMainPage()
    local pages = { CreateNameplatesPage(), CreateTexturesPage(), CreateFontsPage() }

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(mainPanel, mainPanel.name)
        for _, page in ipairs(pages) do
            Settings.RegisterCanvasLayoutSubcategory(category, page, page.name)
        end
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(mainPanel)
        for _, page in ipairs(pages) do
            page.parent = mainPanel.name
            InterfaceOptions_AddCategory(page)
        end
    end
end)

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
        return true
    elseif mainPanel and InterfaceOptionsFrame_OpenToCategory then
        -- called twice: the old frame doesn't scroll to the addon on first open
        InterfaceOptionsFrame_OpenToCategory(mainPanel)
        InterfaceOptionsFrame_OpenToCategory(mainPanel)
        return true
    end
end
