-- Forever Nameplates: threat glow around the stock nameplates.
--   Tank mode (default): safe = you have aggro, warning = losing it, danger = someone else has it.
--   DPS mode:            danger = you have aggro, warning = about to pull, nothing otherwise.

local ADDON, ns = ...
local GLOW_TEXTURE = "Interface\\AddOns\\" .. ADDON .. "\\media\\glow"
local GLOW_MARGIN = 8 -- glow thickness baked into the texture, in texture pixels

local DB_VERSION = 4
local defaults = {
    enabled = true,
    mode = "tank",
    size = 1.0,
    alpha = 0.75,
    colors = {
        safe    = { 0.10, 1.00, 0.20 },
        warning = { 1.00, 0.85, 0.00 },
        danger  = { 1.00, 0.10, 0.10 },
    },
}
ns.defaults = defaults
ns.SIZE_MIN, ns.SIZE_MAX = 0.5, 2.0
ns.ALPHA_MIN, ns.ALPHA_MAX = 0.1, 1.0

local db
local glows = {}      -- [nameplate] = glow frame
local activeUnits = {} -- [unitToken] = nameplate

local function CopyTable(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = type(v) == "table" and CopyTable(v) or v end
    return copy
end

local function ApplyDefaults(target, source)
    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(target[k]) == "table" then
            ApplyDefaults(target[k], v)
        end
    end
end

function ns.ResetSettings()
    for k in pairs(defaults) do db[k] = nil end
    ApplyDefaults(db, defaults)
end

---------------------------------------------------------------------------
-- Threat -> color
---------------------------------------------------------------------------

local function IsGroupMember(unit)
    return UnitIsUnit(unit, "pet") or UnitInParty(unit) or UnitInRaid(unit)
end

local function GetThreatColor(unit)
    if not UnitCanAttack("player", unit) or UnitIsDeadOrGhost(unit) then return end
    local colors = db.colors

    -- 3 = securely tanking, 2 = tanking but about to lose it,
    -- 1 = not tanking but above the tank, 0 = not tanking. nil = not on its threat table.
    local status = UnitThreatSituation("player", unit)

    if db.mode == "dps" then
        if status == 3 or status == 2 then return colors.danger end
        if status == 1 then return colors.warning end
        return
    end

    if status == 3 then return colors.safe end
    if status == 2 or status == 1 then return colors.warning end
    if status == 0 then return colors.danger end

    -- Not on its threat table yet, but it's already beating on a groupmate.
    if UnitAffectingCombat(unit) then
        local target = unit .. "target"
        if UnitExists(target) and not UnitIsUnit(target, "player") and IsGroupMember(target) then
            return colors.danger
        end
    end
end

---------------------------------------------------------------------------
-- Glow frame
---------------------------------------------------------------------------

local function GetHealthBar(unitFrame)
    return unitFrame.healthBar
        or (unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar)
        or unitFrame
end

-- Creates a (hidden) glow behind `anchor`. Also used by the options preview.
function ns.CreateGlow(parent, anchor)
    local glow = CreateFrame("Frame", nil, parent)
    glow:SetFrameLevel(math.max(0, anchor:GetFrameLevel() - 1))
    glow.anchor = anchor

    local tex = glow:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(GLOW_TEXTURE)
    tex:SetBlendMode("ADD")
    if tex.SetTextureSliceMargins then
        tex:SetTextureSliceMargins(GLOW_MARGIN, GLOW_MARGIN, GLOW_MARGIN, GLOW_MARGIN)
        if tex.SetTextureSliceMode and Enum.UITextureSliceMode then
            tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    end
    glow.tex = tex
    glow:Hide()
    return glow
end

function ns.LayoutGlow(glow)
    -- The glow frame is scaled, so offsets below are in texture pixels and
    -- stay in sync with the slice margins at any size.
    glow:SetScale(db.size)
    glow.tex:ClearAllPoints()
    glow.tex:SetPoint("TOPLEFT", glow.anchor, "TOPLEFT", -GLOW_MARGIN, GLOW_MARGIN)
    glow.tex:SetPoint("BOTTOMRIGHT", glow.anchor, "BOTTOMRIGHT", GLOW_MARGIN, -GLOW_MARGIN)
end

function ns.ColorGlow(glow, color)
    glow.tex:SetVertexColor(color[1], color[2], color[3], db.alpha)
end

local function GetGlow(namePlate)
    local glow = glows[namePlate]
    if glow then return glow end

    local unitFrame = namePlate.UnitFrame
    if not unitFrame then return end

    glow = ns.CreateGlow(unitFrame, GetHealthBar(unitFrame))
    glows[namePlate] = glow
    return glow
end

local function UpdateUnit(unit)
    local namePlate = activeUnits[unit]
    if not namePlate then return end
    local glow = glows[namePlate]
    if not glow then return end

    local color = db.enabled and GetThreatColor(unit)
    if color then
        ns.ColorGlow(glow, color)
        glow:Show()
    else
        glow:Hide()
    end
end

local function UpdateAll()
    for unit in pairs(activeUnits) do UpdateUnit(unit) end
end

-- Call after changing any setting.
function ns.Refresh()
    for _, glow in pairs(glows) do ns.LayoutGlow(glow) end
    UpdateAll()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")

local function OnNamePlateAdded(unit)
    local namePlate = C_NamePlate.GetNamePlateForUnit(unit)
    if not namePlate or (namePlate.IsForbidden and namePlate:IsForbidden()) then return end

    local glow = GetGlow(namePlate)
    if not glow then return end
    ns.LayoutGlow(glow)
    activeUnits[unit] = namePlate
    UpdateUnit(unit)
end

local function OnNamePlateRemoved(unit)
    local namePlate = activeUnits[unit]
    activeUnits[unit] = nil
    if namePlate and glows[namePlate] then glows[namePlate]:Hide() end
end

f:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit ~= ADDON then return end
        ForeverNameplatesDB = ForeverNameplatesDB or {}
        db = ForeverNameplatesDB
        local version = db.version or 1
        if version < 2 then
            -- Glow texture changed; old size/alpha values no longer look right.
            db.size, db.alpha = nil, nil
        elseif version < 3 then
            db.size = nil -- default glow size bumped
        end
        db.version = DB_VERSION
        ApplyDefaults(db, defaults)
        ns.db = db
        if ns.CreateOptions then ns.CreateOptions() end
        f:UnregisterEvent("ADDON_LOADED")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        OnNamePlateAdded(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        OnNamePlateRemoved(unit)
    elseif unit and activeUnits[unit] then
        UpdateUnit(unit)
    else
        UpdateAll()
    end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
f:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE") -- fires for the player; refresh everything
f:RegisterEvent("UNIT_TARGET")
f:RegisterEvent("UNIT_FLAGS")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")

-- Light safety net while in combat, for anything events miss.
local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    if db and db.enabled and InCombatLockdown() then UpdateAll() end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

function ns.Print(msg)
    print("|cff33ff66Forever Nameplates:|r " .. msg)
end
local Print = ns.Print

SLASH_FOREVERNAMEPLATES1 = "/fnp"
SlashCmdList.FOREVERNAMEPLATES = function(input)
    local cmd, arg = strsplit(" ", strlower(strtrim(input or "")), 2)
    if cmd == "toggle" then
        db.enabled = not db.enabled
        Print(db.enabled and "enabled" or "disabled")
    elseif cmd == "tank" or cmd == "dps" then
        db.mode = cmd
        Print("mode set to " .. cmd)
    elseif cmd == "size" and tonumber(arg) then
        db.size = math.min(ns.SIZE_MAX, math.max(ns.SIZE_MIN, tonumber(arg)))
        Print("glow thickness set to " .. db.size)
    elseif cmd == "alpha" and tonumber(arg) then
        db.alpha = math.min(ns.ALPHA_MAX, math.max(ns.ALPHA_MIN, tonumber(arg)))
        Print("glow opacity set to " .. db.alpha)
    elseif cmd == "reset" then
        ns.ResetSettings()
        Print("settings reset")
    elseif cmd == "help" then
        Print("/fnp (options) | tank | dps | toggle | size <0.5-2> | alpha <0.1-1> | reset")
        return
    else
        if ns.OpenOptions and ns.OpenOptions() then return end
        Print("/fnp tank | dps | toggle | size <0.5-2> | alpha <0.1-1> | reset")
        return
    end
    ns.Refresh()
end
