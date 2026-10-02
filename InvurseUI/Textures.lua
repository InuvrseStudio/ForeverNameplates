-- Textures: flat status bar textures for the unit frames, raid frames and damage meter.
-- (Nameplate health bars are handled in Nameplates.lua, using ns.GetBarTexture.)

local ADDON, ns = ...

ns.TEXTURE_STYLES = {
    { key = "blizzard", label = "Blizzard default" },
    { key = "flat",     label = "Flat",   path = "Interface\\Buttons\\WHITE8X8" },
    { key = "smooth",   label = "Smooth", path = ns.MEDIA .. "smooth" },
}

local paths = {}
for _, style in ipairs(ns.TEXTURE_STYLES) do paths[style.key] = style.path end

-- Returns the texture to use for an area ("unitFrames", "raidFrames", "damageMeter",
-- "nameplates"), or nil to leave Blizzard's texture alone.
function ns.GetBarTexture(area)
    local settings = ns.db.textures
    if settings[area] then return paths[settings.style] end
end
local GetBarTexture = ns.GetBarTexture

---------------------------------------------------------------------------
-- Player, target, focus, pet and party frames
---------------------------------------------------------------------------

local UNIT_FRAMES = { "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "TargetFrameToT", "FocusFrameToT" }

-- Blizzard's mana bars bake the power color into the bar art and tint it white,
-- so a plain texture needs the power color applied by hand.
local function StyleManaBar(manaBar)
    local texture = manaBar and manaBar.unit and GetBarTexture("unitFrames")
    if not texture then return end
    manaBar:SetStatusBarTexture(texture)

    local _, powerToken, altR, altG, altB = UnitPowerType(manaBar.unit)
    local info = PowerBarColor and (PowerBarColor[powerToken] or PowerBarColor.MANA)
    if info and info.r then
        manaBar:SetStatusBarColor(info.r, info.g, info.b)
    elseif altR then
        manaBar:SetStatusBarColor(altR, altG, altB)
    end
end

ns.HEALTH_COLORS = {
    { key = "green", label = "Green" },
    { key = "class", label = "Class color  (players; others stay green)" },
}
local HEALTH_GREEN = { r = 0.0, g = 1.0, b = 0.0 } -- the classic unit frame green
local DISCONNECTED_GREY = { r = 0.5, g = 0.5, b = 0.5 }

local function GetHealthColor(unit)
    if not UnitIsConnected(unit) then return DISCONNECTED_GREY end
    if ns.db.textures.healthColor == "class" and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local color = class and RAID_CLASS_COLORS[class]
        if color then return color end
    end
    return HEALTH_GREEN
end

-- Same story for health: these bars set lockColor and rely on green bar art, so
-- with a plain texture we color them ourselves.
local function StyleHealthBar(healthBar)
    local texture = healthBar and healthBar.unit and GetBarTexture("unitFrames")
    if not texture then return end
    healthBar:SetStatusBarTexture(texture)
    local color = GetHealthColor(healthBar.unit)
    healthBar:SetStatusBarColor(color.r, color.g, color.b)
end

local function StyleUnitFrame(frame)
    if not frame then return end
    StyleHealthBar(frame.healthbar)
    StyleManaBar(frame.manabar)
end

local function StyleUnitFrames()
    for _, name in ipairs(UNIT_FRAMES) do StyleUnitFrame(_G[name]) end
    if PartyFrame then
        for i = 1, MAX_PARTY_MEMBERS or 4 do StyleUnitFrame(PartyFrame["MemberFrame" .. i]) end
    end
end

---------------------------------------------------------------------------
-- Raid frames (and the raid-style party frames)
---------------------------------------------------------------------------

local function StyleCompactFrame(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local texture = GetBarTexture("raidFrames")
    if not texture then return end
    if frame.healthBar then frame.healthBar:SetStatusBarTexture(texture) end
    if frame.powerBar then frame.powerBar:SetStatusBarTexture(texture) end
end

local function StyleCompactFrames()
    for i = 1, 5 do
        StyleCompactFrame(_G["CompactPartyFrameMember" .. i])
        StyleCompactFrame(_G["CompactPartyFramePet" .. i])
    end
    for i = 1, 40 do StyleCompactFrame(_G["CompactRaidFrame" .. i]) end
    for group = 1, 8 do
        for i = 1, 5 do StyleCompactFrame(_G["CompactRaidGroup" .. group .. "Member" .. i]) end
    end
end

---------------------------------------------------------------------------
-- Damage meter
---------------------------------------------------------------------------

local function StyleMeterEntry(entry)
    local texture = GetBarTexture("damageMeter")
    if texture and entry and entry.StatusBar then entry.StatusBar:SetStatusBarTexture(texture) end
end

local function StyleMeterWindows()
    if not (DamageMeter and DamageMeter.ForEachSessionWindow) then return end
    DamageMeter:ForEachSessionWindow(function(window)
        local scrollBox = window.GetScrollBox and window:GetScrollBox()
        if scrollBox and scrollBox.ForEachFrame then scrollBox:ForEachFrame(StyleMeterEntry) end
        if window.GetLocalPlayerEntry then StyleMeterEntry(window:GetLocalPlayerEntry()) end
    end)
end

local meterHooked = false
local function HookDamageMeter()
    if meterHooked or not DamageMeterSourceEntryMixin then return end
    meterHooked = true
    -- Entries are pooled and re-styled every time they're acquired; hooking the
    -- mixins covers every entry created from here on.
    for _, mixin in ipairs({ DamageMeterSourceEntryMixin, DamageMeterSpellEntryMixin }) do
        if mixin and mixin.SetStyle then hooksecurefunc(mixin, "SetStyle", StyleMeterEntry) end
    end
    StyleMeterWindows()
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local function StyleAll()
    StyleUnitFrames()
    StyleCompactFrames()
    StyleMeterWindows()
end

-- Swapping between our textures is live; going back to Blizzard's needs a reload,
-- since their art differs per frame and per power type.
local RELOAD_AREAS = { "unitFrames", "raidFrames", "damageMeter" }
local applied = {} -- what's currently on screen: [area] = texture path or nil

local function RememberApplied()
    for _, area in ipairs(RELOAD_AREAS) do applied[area] = GetBarTexture(area) end
end

ns.OnInit(function()
    RememberApplied()
    hooksecurefunc("UnitFrameHealthBar_Update", StyleHealthBar)
    hooksecurefunc("UnitFrameManaBar_UpdateType", StyleManaBar)
    if UnitFrameManaBar_UpdateTypeOld then hooksecurefunc("UnitFrameManaBar_UpdateTypeOld", StyleManaBar) end
    hooksecurefunc("DefaultCompactUnitFrameSetup", StyleCompactFrame)
    if DefaultCompactMiniFrameSetup then hooksecurefunc("DefaultCompactMiniFrameSetup", StyleCompactFrame) end
    HookDamageMeter()

    ns.On("ADDON_LOADED", function(_, name)
        if name == "Blizzard_DamageMeter" then HookDamageMeter() end
    end)
    ns.On("PLAYER_ENTERING_WORLD", StyleAll)
    ns.On("GROUP_ROSTER_UPDATE", StyleAll)
    ns.On("PLAYER_TARGET_CHANGED", StyleUnitFrames)
    ns.On("PLAYER_FOCUS_CHANGED", StyleUnitFrames)
end)

ns.OnRefresh(function()
    local needsReload = false
    for _, area in ipairs(RELOAD_AREAS) do
        if applied[area] and not GetBarTexture(area) then needsReload = true end
    end
    RememberApplied()
    StyleAll()
    if needsReload then ns.RequestReload() end
end)
