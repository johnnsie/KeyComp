local addonName, ns = ...
ns.version = "0.1.0"

local defaults = {
    point    = nil,                  -- saved frame position
    dungeon  = "MAGISTERS_TERRACE",  -- last selected dungeon
    auto     = true,                 -- auto-detect dungeon when inside one
    shown    = true,                 -- panel visible
    autoShow = true,                 -- pop the panel while forming a group
    minimapHide  = false,            -- minimap button hidden
    minimapAngle = 220,              -- minimap button position (degrees around rim)
}

local lastGroupSize = 0

local refreshTicker
local function startRefreshTicker()
    if refreshTicker or not (C_Timer and C_Timer.NewTicker) then return end
    refreshTicker = C_Timer.NewTicker(3, function()
        -- re-render FIRST so a RefreshApplicants error can't abort the tick
        if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
            ns.UI:Refresh()
        end
        -- then ask the server for fresh applicant data (error-safe)
        if C_LFGList and C_LFGList.HasActiveEntry and C_LFGList.HasActiveEntry()
            and C_LFGList.RefreshApplicants then
            pcall(C_LFGList.RefreshApplicants)
        end
    end)
end

local f = CreateFrame("Frame")
ns.eventFrame = f

local function reg(ev) pcall(f.RegisterEvent, f, ev) end
reg("ADDON_LOADED")
reg("PLAYER_LOGIN")
reg("PLAYER_ENTERING_WORLD")
reg("GROUP_ROSTER_UPDATE")
reg("PLAYER_SPECIALIZATION_CHANGED")
reg("PLAYER_ROLES_ASSIGNED")
reg("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
reg("CHALLENGE_MODE_START")
reg("LFG_LIST_ACTIVE_ENTRY_UPDATE")
reg("LFG_LIST_APPLICANT_LIST_UPDATED")
reg("LFG_LIST_APPLICANT_UPDATED")

local function inInstanceNow()
    if not IsInInstance then return false end
    local inside = IsInInstance()
    return inside and true or false
end

local function hasListing()
    return C_LFGList and C_LFGList.HasActiveEntry and C_LFGList.HasActiveEntry()
end

-- "forming a group" = not inside an instance, not yet full, and either already
-- grouped or actively advertising a group in Premade Group Finder.
local function formingNow()
    if inInstanceNow() then return false end
    local size = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if size >= 5 then return false end
    return size >= 2 or hasListing()
end

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            KeyCompDB = KeyCompDB or {}
            for k, v in pairs(defaults) do
                if KeyCompDB[k] == nil then KeyCompDB[k] = v end
            end
            ns.db = KeyCompDB
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        ns.UI:Init()
        if ns.Minimap then ns.Minimap:Init() end
        startRefreshTicker()
        if ns.db.shown then ns.UI:Show() else ns.UI:Refresh() end
        return
    end

    if ns.UI then ns.UI:Refresh() end

    if event == "GROUP_ROSTER_UPDATE" then
        local size = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        if ns.db and ns.db.autoShow and formingNow() and size > lastGroupSize then
            ns.UI:Show()
        end
        lastGroupSize = size
    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        if ns.db and ns.db.autoShow and formingNow() then
            ns.UI:Show()
        end
    end
end)

SLASH_KEYCOMP1 = "/keycomp"
SLASH_KEYCOMP2 = "/kc"
SlashCmdList["KEYCOMP"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s*(.-)%s*$", "%1")
    if msg == "show" then
        ns.UI:Show()
    elseif msg == "hide" then
        ns.UI:Hide()
    elseif msg == "auto" then
        ns.db.autoShow = not ns.db.autoShow
        print("|cff66ccffKeyComp|r auto-open while forming: " .. (ns.db.autoShow and "ON" or "OFF"))
    elseif msg == "minimap" then
        if ns.Minimap then
            local shown = ns.Minimap:Toggle()
            print("|cff66ccffKeyComp|r minimap button: " .. (shown and "ON" or "OFF"))
        end
    elseif msg == "debug" then
        if ns.UI and ns.UI.Debug then ns.UI:Debug() end
    else
        ns.UI:Toggle()
    end
end
