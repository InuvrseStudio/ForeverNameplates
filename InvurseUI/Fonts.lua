-- Fonts: swap the font face used across the standard UI, keeping each font's size and outline.

local ADDON, ns = ...

local BUILTIN_FONTS = {
    { key = "default",  label = "Blizzard default" },
    { key = "friz",     label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arialn",   label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "skurri",   label = "Skurri",        path = "Fonts\\skurri.ttf" },
    { key = "morpheus", label = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    -- Bundled in media\fonts (SIL Open Font License, see Roboto-OFL.txt there).
    { key = "roboto",          label = "Roboto",                path = ns.MEDIA .. "fonts\\Roboto-Regular.ttf" },
    { key = "roboto-medium",   label = "Roboto Medium",         path = ns.MEDIA .. "fonts\\Roboto-Medium.ttf" },
    { key = "roboto-bold",     label = "Roboto Bold",           path = ns.MEDIA .. "fonts\\Roboto-Bold.ttf" },
    { key = "roboto-cond",     label = "Roboto Condensed",      path = ns.MEDIA .. "fonts\\RobotoCondensed-Regular.ttf" },
    { key = "roboto-condbold", label = "Roboto Condensed Bold", path = ns.MEDIA .. "fonts\\RobotoCondensed-Bold.ttf" },
}

-- Built-in fonts, plus any registered with LibSharedMedia by other addons.
function ns.GetFontList()
    local list = {}
    for _, font in ipairs(BUILTIN_FONTS) do table.insert(list, font) end

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local known = {}
        for _, font in ipairs(BUILTIN_FONTS) do
            if font.path then known[strlower(font.path)] = true end
        end
        local extra = {}
        for name, path in pairs(LSM:HashTable("font")) do
            if not known[strlower(path)] then
                table.insert(extra, { key = "lsm:" .. name, label = name, path = path })
            end
        end
        table.sort(extra, function(a, b) return a.label < b.label end)
        for _, font in ipairs(extra) do table.insert(list, font) end
    end
    return list
end

function ns.GetFontPath(key)
    for _, font in ipairs(ns.GetFontList()) do
        if font.key == key then return font.path end
    end
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------

local originals = {} -- [fontObject] = original font file
local originalGlobals = {}
local FONT_GLOBALS = { "STANDARD_TEXT_FONT", "UNIT_NAME_FONT", "NAMEPLATE_FONT", "DAMAGE_TEXT_FONT" }

local function SetFace(fontObject, path)
    local file, size, flags = fontObject:GetFont()
    if not file then return end -- font families without a face of their own
    if not originals[fontObject] then originals[fontObject] = file end
    fontObject:SetFont(path or originals[fontObject], size, flags or "")
end

local function ApplyFonts()
    local path = ns.GetFontPath(ns.db.fonts.face)
    if not path and not next(originals) then return end -- default and never changed

    for _, name in ipairs(GetFonts and GetFonts() or {}) do
        local fontObject = _G[name]
        if type(fontObject) == "table" and fontObject.GetFont then
            pcall(SetFace, fontObject, path)
        end
    end

    -- Read by other addons when they create text, and by the game for combat text (that one needs a relog).
    if not originalGlobals.saved then
        originalGlobals.saved = true
        for _, key in ipairs(FONT_GLOBALS) do originalGlobals[key] = _G[key] end
    end
    for _, key in ipairs(FONT_GLOBALS) do
        _G[key] = path or originalGlobals[key]
    end
end

ns.OnInit(function()
    ApplyFonts()
    -- Catch font objects other addons create while loading.
    ns.On("PLAYER_LOGIN", ApplyFonts)
end)

ns.OnRefresh(ApplyFonts)
