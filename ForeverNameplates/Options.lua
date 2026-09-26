-- Options panel (Esc > Options > AddOns > Forever Nameplates, or /fnp).

local ADDON, ns = ...

local COLOR_ROWS = {
    { key = "safe",    label = "Safe",    desc = "Tank: you have aggro" },
    { key = "warning", label = "Warning", desc = "Aggro is about to change hands" },
    { key = "danger",  label = "Danger",  desc = "Tank: someone else has aggro  |  DPS: you pulled it" },
}

local panel, category
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
        OpenColorPicker(ns.db.colors[row.key], function(r, g, b)
            local c = ns.db.colors[row.key]
            c[1], c[2], c[3] = r, g, b
            ns.Refresh()
        end)
    end)
    return btn
end

local function PreviewBar(parent, x, y)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetPoint("TOPLEFT", x, y)
    bar:SetSize(120, 12)
    bar:SetFrameLevel(parent:GetFrameLevel() + 5)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.75, 0.05, 0.05)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.6)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 1)

    -- thin dark border, roughly like the stock plate
    local border = CreateFrame("Frame", nil, bar)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(bar:GetFrameLevel() - 1)
    local bt = border:CreateTexture(nil, "BACKGROUND")
    bt:SetAllPoints()
    bt:SetColorTexture(0, 0, 0, 1)

    bar.glow = ns.CreateGlow(parent, border)
    bar.glow:SetFrameLevel(math.max(0, border:GetFrameLevel() - 1))
    return bar
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

function ns.RefreshOptions()
    if not panel then return end
    local db = ns.db
    widgets.enabled:SetChecked(db.enabled)
    widgets.tank:SetChecked(db.mode == "tank")
    widgets.dps:SetChecked(db.mode == "dps")
    widgets.size:SetValue(db.size)
    widgets.alpha:SetValue(db.alpha)
    for _, row in ipairs(COLOR_ROWS) do
        local c = db.colors[row.key]
        widgets[row.key].swatch:SetColorTexture(c[1], c[2], c[3], 1)
        local bar = widgets.preview[row.key]
        ns.LayoutGlow(bar.glow)
        ns.ColorGlow(bar.glow, c)
        bar.glow:SetShown(db.enabled)
    end
end

local function Set(key, value)
    ns.db[key] = value
    ns.Refresh()
end

function ns.CreateOptions()
    panel = CreateFrame("Frame")
    panel.name = "Forever Nameplates"
    panel:SetScript("OnShow", ns.RefreshOptions)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Forever Nameplates")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Threat glow around the stock nameplates.")

    widgets.enabled = Checkbox(panel, "Enable threat glow", 16, -60, function(on) Set("enabled", on) end)

    Header(panel, "Mode", 16, -100)
    widgets.tank = Checkbox(panel, "Tank  (show who has aggro on every mob)", 16, -118,
        function() Set("mode", "tank") end)
    widgets.dps = Checkbox(panel, "DPS / Healer  (only warn when you're pulling aggro)", 16, -144,
        function() Set("mode", "dps") end)

    Header(panel, "Appearance", 16, -186)
    widgets.size = Slider(panel, "Glow thickness", 20, -206, ns.SIZE_MIN, ns.SIZE_MAX, 0.05,
        function(v) Set("size", v) end)
    widgets.alpha = Slider(panel, "Glow opacity", 20, -262, ns.ALPHA_MIN, ns.ALPHA_MAX, 0.05,
        function(v) Set("alpha", v) end)

    Header(panel, "Colors", 16, -320)
    for i, row in ipairs(COLOR_ROWS) do
        widgets[row.key] = ColorSwatch(panel, row, 20, -342 - (i - 1) * 30)
    end

    Header(panel, "Preview", 300, -186)
    widgets.preview = {}
    for i, row in ipairs(COLOR_ROWS) do
        local y = -216 - (i - 1) * 38
        widgets.preview[row.key] = PreviewBar(panel, 310, y)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", 440, y)
        label:SetText(row.label)
    end

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetPoint("TOPLEFT", 16, -448)
    reset:SetSize(140, 24)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function()
        ns.ResetSettings()
        ns.Refresh()
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    hint:SetText("Type /fnp to open this panel.")

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
        return true
    elseif panel and InterfaceOptionsFrame_OpenToCategory then
        -- called twice: the old frame doesn't scroll to the addon on first open
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
        return true
    end
end
