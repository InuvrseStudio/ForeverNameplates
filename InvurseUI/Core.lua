-- InvurseUI: subtle tweaks to the stock Blizzard UI.
-- Core: saved settings, a small event dispatcher and the slash command.

local ADDON, ns = ...

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"

local DB_VERSION = 1
local defaults = {
    threat = {
        enabled = true,
        mode = "tank",
        size = 1.0,
        alpha = 0.75,
        colors = {
            safe    = { 0.10, 1.00, 0.20 },
            warning = { 1.00, 0.85, 0.00 },
            danger  = { 1.00, 0.10, 0.10 },
        },
    },
    nameplates = {
        levelBesideName = true,
    },
    textures = {
        style = "flat",
        healthColor = "green",
        unitFrames = true,
        raidFrames = true,
        damageMeter = true,
        nameplates = false,
    },
    fonts = {
        face = "default",
    },
}
ns.defaults = defaults

local db

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

-- Resets one section (e.g. "threat"), or everything when section is nil.
function ns.ResetSettings(section)
    if section then
        db[section] = CopyTable(defaults[section])
        return
    end
    for k in pairs(defaults) do db[k] = nil end
    ApplyDefaults(db, defaults)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Registers fn(event, ...) for an event. Several modules can share one event.
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do fn(event, ...) end
end)

-- Modules register an init function, run once the saved settings are loaded.
local initializers = {}
function ns.OnInit(fn) table.insert(initializers, fn) end

-- Modules register a refresh function, run after any setting changes.
local refreshers = {}
function ns.OnRefresh(fn) table.insert(refreshers, fn) end

function ns.Refresh()
    for _, fn in ipairs(refreshers) do fn() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON or db then return end
    InvurseUIDB = InvurseUIDB or {}
    db = InvurseUIDB
    db.version = DB_VERSION
    ApplyDefaults(db, defaults)
    ns.db = db
    for _, fn in ipairs(initializers) do fn() end
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.Print(msg)
    print("|cff33ff66InvurseUI:|r " .. msg)
end
local Print = ns.Print

-- Some changes (like going back to Blizzard's bar textures) are only clean after a reload.
StaticPopupDialogs["INVURSEUI_RELOAD"] = {
    text = "InvurseUI: reload the UI to finish applying this change?",
    button1 = RELOADUI or "Reload UI",
    button2 = LATER or "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function ns.RequestReload()
    StaticPopup_Show("INVURSEUI_RELOAD")
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local HELP = "/iui (options) | tank | dps | toggle | size <0.5-2> | alpha <0.1-1> | reset"

local function OnSlash(input)
    local cmd, arg = strsplit(" ", strlower(strtrim(input or "")), 2)
    local threat = db.threat
    if cmd == "toggle" then
        threat.enabled = not threat.enabled
        Print("threat glow " .. (threat.enabled and "enabled" or "disabled"))
    elseif cmd == "tank" or cmd == "dps" then
        threat.mode = cmd
        Print("threat mode set to " .. cmd)
    elseif cmd == "size" and tonumber(arg) then
        threat.size = math.min(ns.SIZE_MAX, math.max(ns.SIZE_MIN, tonumber(arg)))
        Print("glow thickness set to " .. threat.size)
    elseif cmd == "alpha" and tonumber(arg) then
        threat.alpha = math.min(ns.ALPHA_MAX, math.max(ns.ALPHA_MIN, tonumber(arg)))
        Print("glow opacity set to " .. threat.alpha)
    elseif cmd == "reset" then
        ns.ResetSettings()
        Print("settings reset")
    elseif cmd == "help" then
        Print(HELP)
        return
    else
        if ns.OpenOptions and ns.OpenOptions() then return end
        Print(HELP)
        return
    end
    ns.Refresh()
end

SLASH_INVURSEUI1 = "/iui"
SLASH_INVURSEUI2 = "/invurseui"
SLASH_INVURSEUI3 = "/fnp" -- kept from Forever Nameplates
SlashCmdList.INVURSEUI = OnSlash
