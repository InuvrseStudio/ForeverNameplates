-- Nameplates: threat glow around the stock nameplates, and the level shown beside the name.
--   Tank mode (default): safe = you have aggro, warning = losing it, danger = someone else has it.
--   DPS mode:            danger = you have aggro, warning = about to pull, nothing otherwise.

local ADDON, ns = ...
local GLOW_TEXTURE = ns.MEDIA .. "glow"
local GLOW_MARGIN = 8 -- glow thickness baked into the texture, in texture pixels

ns.SIZE_MIN, ns.SIZE_MAX = 0.5, 2.0
ns.ALPHA_MIN, ns.ALPHA_MAX = 0.1, 1.0

local db -- ns.db.threat
local glows = {}      -- [nameplate] = glow frame
local activeUnits = {} -- [unitToken] = nameplate

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

---------------------------------------------------------------------------
-- Level beside the name ("16 - Forest Spider")
---------------------------------------------------------------------------

-- WoW Forever shows the level in a box to the right of the health bar
-- (PlayerLevelDiffFrame) and shrinks the bar to make room for it. With the level
-- moved next to the name we hide that box and give the bar its full width back.
-- The Classic style also draws a level slot into the bar's border; there we close
-- the border with a mirrored copy of its left end cap.
local BORDER_TEXTURE = "Interface\\Tooltips\\Nameplate-Border"
local CLASSIC_BAR_INSET = 3.5 -- matches Blizzard's NamePlateUnitFrameMixin:UpdateAnchors
local CLASSIC_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local MODERN_BAR_ATLAS = "UI-HUD-CoolDownManager-Bar"
local AURA_GAP = 5 -- gap Blizzard leaves between the bar and the crowd-control auras

local function IsNamePlateFrame(frame)
    local unit = frame.unit
    return ns.db and unit and strsub(unit, 1, 9) == "nameplate"
        and not (frame.IsForbidden and frame:IsForbidden())
end

local function ShouldMoveLevel()
    return ns.db.nameplates.levelBesideName
end

local function GetLevelText(frame)
    local unit = frame.unit
    local level = UnitEffectiveLevel(unit)
    if not level or level <= 0 then
        return "|cffff2020??|r" -- too high to tell, like the skull icon
    end

    -- Same colors as Blizzard's level box.
    local color = UNIT_LEVEL_NON_ATTACKABLE or NORMAL_FONT_COLOR
    if UnitCanAttack("player", unit) then
        local levelFrame = frame.PlayerLevelDiffFrame
        if levelFrame and levelFrame.GetDifficultyColor then
            color = levelFrame:GetDifficultyColor(level - UnitEffectiveLevel("player"))
        elseif GetRelativeDifficultyColor then
            color = GetRelativeDifficultyColor(UnitEffectiveLevel("player"), level)
        end
    end

    local classification = UnitClassification(unit)
    local elite = (classification == "elite" or classification == "rareelite" or classification == "worldboss") and "+" or ""
    return format("|cff%02x%02x%02x%d%s|r", color.r * 255, color.g * 255, color.b * 255, level, elite)
end

local function UpdateNameLevel(frame)
    if not IsNamePlateFrame(frame) or not frame.name then return end

    -- Blizzard writes the plain name; remember it so we can rebuild or restore it later.
    local current = frame.name:GetText()
    if current and current ~= frame.iuiLevelName then
        frame.iuiBaseName = current
    end
    local base = frame.iuiBaseName
    if not base then return end

    if ShouldMoveLevel() then
        local text = GetLevelText(frame) .. " - " .. base
        frame.iuiLevelName = text
        frame.name:SetText(text)
    elseif current == frame.iuiLevelName then
        frame.iuiLevelName = nil
        frame.name:SetText(base)
    end
end

local function HideLevelBoxes(frame)
    if frame.PlayerLevelDiffFrame then frame.PlayerLevelDiffFrame:Hide() end
    if frame.LevelFrame then frame.LevelFrame:Hide() end
end

local function GetBorderPieces(healthBar)
    if healthBar.iuiBorderLeft then
        return healthBar.iuiBorderLeft, healthBar.iuiBorderRight
    end
    local bg = healthBar.bgTexture

    local left = healthBar:CreateTexture(nil, "ARTWORK", nil, 1)
    left:SetTexture(BORDER_TEXTURE)
    left:SetTexCoord(0, 0.5, 0.5, 1)
    left:SetPoint("TOPLEFT", bg, "TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", bg, "BOTTOM")

    local right = healthBar:CreateTexture(nil, "ARTWORK", nil, 1)
    right:SetTexture(BORDER_TEXTURE)
    right:SetTexCoord(0.5, 0, 0.5, 1) -- left half, mirrored
    right:SetPoint("TOPLEFT", bg, "TOP")
    right:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT")

    healthBar.iuiBorderLeft, healthBar.iuiBorderRight = left, right
    return left, right
end

-- Undoes the room Blizzard reserved for the level box (see UpdateAnchors).
local function ReclaimLevelSpace(unitFrame, opts)
    local container = unitFrame.HealthBarsContainer
    local healthBar = container.healthBar
    HideLevelBoxes(unitFrame)

    container:SetPoint("BOTTOMRIGHT", unitFrame.CastBarsContainer, "TOPRIGHT", 0, opts.castBarToHealthBarSpacing)

    local auras = unitFrame.AurasFrame
    if auras then
        if auras.CrowdControlListFrame then auras.CrowdControlListFrame:SetPoint("LEFT", container, "RIGHT", AURA_GAP, 0) end
        if auras.LossOfControlFrame then auras.LossOfControlFrame:SetPoint("LEFT", container, "RIGHT", AURA_GAP, 0) end
    end

    -- Blizzard caps the name at the bar's width (or the level box); let "16 - Name" use what it needs.
    local insideBar = opts.unitNameAnchorStyle == NamePlateConstants.NAME_ANCHOR_STYLES.InsideHealthBar
    if not insideBar and not (unitFrame.IsShowOnlyName and unitFrame:IsShowOnlyName()) then
        unitFrame.name:ClearAllPoints()
        unitFrame.name:SetPoint("BOTTOM", container, "TOP", 0, opts.healthBarToNameAboveSpacing)
    end

    if opts.useClassicHealthBar and healthBar.bgTexture then
        local left, right = GetBorderPieces(healthBar)
        healthBar:ClearAllPoints()
        healthBar:SetPoint("TOPLEFT", container, "TOPLEFT", CLASSIC_BAR_INSET * opts.horizontalScale, 0.5 * opts.verticalScale)
        healthBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -CLASSIC_BAR_INSET * opts.horizontalScale, 0.5 * opts.verticalScale)
        healthBar.bgTexture:SetAlpha(0)
        left:Show()
        right:Show()
    elseif healthBar.iuiBorderLeft then
        -- Switched away from the Classic style.
        healthBar.bgTexture:SetAlpha(1)
        healthBar.iuiBorderLeft:Hide()
        healthBar.iuiBorderRight:Hide()
    end
end

-- Runs after Blizzard lays out a nameplate.
local function LayoutNamePlate(unitFrame)
    if unitFrame:IsForbidden() then return end
    local opts = NamePlateSetupOptions
    local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
    if not healthBar or not opts then return end

    -- Turning this back off is handled by a UI reload (see OnRefresh below).
    if ShouldMoveLevel() then ReclaimLevelSpace(unitFrame, opts) end

    -- Health bar texture (Textures module setting).
    local texture = ns.GetBarTexture("nameplates")
    if texture then
        healthBar:SetStatusBarTexture(texture)
        healthBar.iuiTextured = true
    elseif healthBar.iuiTextured then
        healthBar.iuiTextured = nil
        if opts.useClassicHealthBar then
            healthBar:SetStatusBarTexture(CLASSIC_BAR_TEXTURE)
        else
            healthBar.barTexture:SetAtlas(MODERN_BAR_ATLAS, true)
        end
    end
end

local hookedPlates = {}

local function SetUpNamePlate(unitFrame)
    if not hookedPlates[unitFrame] and unitFrame.UpdateAnchors then
        hookedPlates[unitFrame] = true
        hooksecurefunc(unitFrame, "UpdateAnchors", LayoutNamePlate)
    end
    LayoutNamePlate(unitFrame)
    UpdateNameLevel(unitFrame)
end

hooksecurefunc("CompactUnitFrame_UpdateName", UpdateNameLevel)

-- Blizzard re-shows the level boxes whenever the level updates.
local function OnLevelUpdated(frame)
    if not IsNamePlateFrame(frame) then return end
    if ShouldMoveLevel() then HideLevelBoxes(frame) end
    UpdateNameLevel(frame)
end
hooksecurefunc("CompactUnitFrame_UpdateLevel", OnLevelUpdated)
if CompactUnitFrame_UpdatePlayerLevelDiff then
    hooksecurefunc("CompactUnitFrame_UpdatePlayerLevelDiff", OnLevelUpdated)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function OnNamePlateAdded(_, unit)
    local namePlate = C_NamePlate.GetNamePlateForUnit(unit)
    if not namePlate or (namePlate.IsForbidden and namePlate:IsForbidden()) then return end
    if namePlate.UnitFrame then SetUpNamePlate(namePlate.UnitFrame) end

    local glow = GetGlow(namePlate)
    if not glow then return end
    ns.LayoutGlow(glow)
    activeUnits[unit] = namePlate
    UpdateUnit(unit)
end

local function OnNamePlateRemoved(_, unit)
    local namePlate = activeUnits[unit]
    activeUnits[unit] = nil
    if namePlate and glows[namePlate] then glows[namePlate]:Hide() end
end

local function OnUnitEvent(_, unit)
    if unit and activeUnits[unit] then
        UpdateUnit(unit)
    else
        UpdateAll()
    end
end

ns.OnInit(function()
    db = ns.db.threat

    ns.On("NAME_PLATE_UNIT_ADDED", OnNamePlateAdded)
    ns.On("NAME_PLATE_UNIT_REMOVED", OnNamePlateRemoved)
    ns.On("UNIT_THREAT_LIST_UPDATE", OnUnitEvent)
    ns.On("UNIT_THREAT_SITUATION_UPDATE", OnUnitEvent) -- fires for the player; refresh everything
    ns.On("UNIT_TARGET", OnUnitEvent)
    ns.On("UNIT_FLAGS", OnUnitEvent)
    ns.On("PLAYER_REGEN_ENABLED", OnUnitEvent)
    ns.On("PLAYER_REGEN_DISABLED", OnUnitEvent)
    ns.On("GROUP_ROSTER_UPDATE", OnUnitEvent)

    -- Light safety net while in combat, for anything events miss.
    local elapsed = 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        if db.enabled and InCombatLockdown() then UpdateAll() end
    end)
end)

local levelMoved -- last applied levelBesideName setting
ns.OnInit(function() levelMoved = ShouldMoveLevel() end)

ns.OnRefresh(function()
    db = ns.db.threat -- the table is replaced when its section is reset
    for _, glow in pairs(glows) do ns.LayoutGlow(glow) end
    UpdateAll()
    for unitFrame in pairs(hookedPlates) do
        LayoutNamePlate(unitFrame)
        UpdateNameLevel(unitFrame)
    end
    -- Putting the level box back means redoing Blizzard's whole layout; a reload does that cleanly.
    if levelMoved and not ShouldMoveLevel() then ns.RequestReload() end
    levelMoved = ShouldMoveLevel()
end)
