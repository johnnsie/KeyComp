local addonName, ns = ...
ns.version = "0.1.0"

-- Keybinding -> apply. The body runs in response to the hardware keypress, so the
-- protected C_LFGList.ApplyToGroup inside is allowed (a background timer call is
-- NOT -- that throws "Interface action failed because of an AddOn"). See Bindings.xml.
BINDING_HEADER_KEYQUEUE = "KeyQueue"
BINDING_NAME_KEYQUEUE_APPLYNEXT = "Apply to next best group"
function KeyQueueApplyNext()
    if ns.Queue and ns.Queue.ApplyNext then ns.Queue:ApplyNext() end
end

-- =========================================================================
-- Core: saved vars, the event frame, the ~3s ticker that drives the queue and
-- refreshes the panel, and the slash commands.
-- =========================================================================

local defaults = {
    point   = nil,          -- saved frame position
    shown   = true,         -- panel visible
    scale   = 1,            -- panel scale
    tab     = "queue",      -- queue | listings | settings

    -- queue criteria (the auto-queue defaults to your goal: +19s you still need)
    role        = nil,      -- nil -> derive from spec (HEALER for Disc)
    targetKey   = 19,       -- the key level you're farming
    keyMax      = 19,       -- apply to keys targetKey..keyMax (both 19 = exactly +19)
    autoTargets = true,     -- auto-pick dungeons not yet completed at targetKey
    dungeons    = nil,      -- manual dungeon set (key->bool) when autoTargets = false

    -- auto-apply behaviour
    autoApply      = false, -- timer auto-apply is blocked by Blizzard; off by default
                            -- (apply with the keybind / "Apply to next best" button)
    maxPending     = 5,     -- how many applications to keep in flight at once
    maxApps        = 100,   -- safety cap on total applies per queue session
    minLeaderScore = 0,     -- ignore leaders below this M+ rating (0 = off)
    useOwnSearch   = false, -- drive our own search? OFF = read what YOUR Blizzard
                            -- Group Finder shows (our search overwrites your filter)
    autoRefresh    = true,  -- auto re-run your Group Finder search every few seconds so you
                            -- don't keep clicking refresh (preserves your manual +19 filter)
    skipGated      = true,  -- skip listings whose required rating exceeds yours
    includeUnknownKey = false, -- in auto mode, skip listings with no parseable "+N"
    blacklistMins  = 10,    -- how long to skip a leader after they decline you

    -- optional pitch whispered to the group leader on apply (PGF has no native
    -- applicant note). Off by default -- whispering many groups fast risks a squelch.
    note        = "",
    whisperNote = false,

    minimapAngle = 214,     -- minimap button position, degrees around the ring
    minimapHide  = false,   -- hide the minimap button
}

local refreshTicker
local function startTicker()
    if refreshTicker or not (C_Timer and C_Timer.NewTicker) then return end
    refreshTicker = C_Timer.NewTicker(3, function()
        local uiShown = ns.UI and ns.UI.frame and ns.UI.frame:IsShown()
        if ns.Queue.active then
            pcall(function() ns.Queue:Tick() end)
        elseif uiShown then
            if ns.db and ns.db.autoRefresh ~= false and (ns.db.tab == "queue" or ns.db.tab == "listings") then
                pcall(function() ns.Search:Refresh() end)  -- re-run your search so it stays fresh
            end
            pcall(function() ns.Search:Read() end)    -- refresh cache from your PGF results
        end
        if uiShown then pcall(function() ns.UI:Refresh() end) end
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
reg("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
reg("CHALLENGE_MODE_COMPLETED")
reg("CHALLENGE_MODE_MAPS_UPDATE")
reg("LFG_LIST_SEARCH_RESULTS_RECEIVED")
reg("LFG_LIST_SEARCH_RESULT_UPDATED")
reg("LFG_LIST_APPLICATION_STATUS_UPDATED")
reg("LFG_LIST_ACTIVE_ENTRY_UPDATE")

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            KeyQueueDB = KeyQueueDB or {}
            for k, v in pairs(defaults) do
                if KeyQueueDB[k] == nil then KeyQueueDB[k] = v end
            end
            ns.db = KeyQueueDB
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        if ns.Progress then ns.Progress:Refresh() end
        ns.UI:Init()
        startTicker()
        if ns.db.shown then ns.UI:Show() else ns.UI:Refresh() end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if ns.Progress then ns.Progress:Refresh() end
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_MAPS_UPDATE" then
        -- you just finished a key -> its dungeon may drop off the target list
        if ns.Progress then ns.Progress:Refresh() end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        ns.Search:OnResults()
        ns.Search:Read()
        if ns.Queue.active then pcall(function() ns.Queue:ProcessResults() end) end
    elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        if ns.Queue then pcall(function() ns.Queue:Sync() end) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if ns.Queue.active and GetNumGroupMembers and GetNumGroupMembers() >= 5 then
            ns.Queue:Stop("group is full")
        end
    end

    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
        pcall(function() ns.UI:Refresh() end)
    end
end)

SLASH_KEYQUEUE1 = "/keyqueue"
SLASH_KEYQUEUE2 = "/kq"
SlashCmdList["KEYQUEUE"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s*(.-)%s*$", "%1")
    if msg == "show" then
        ns.UI:Show()
    elseif msg == "hide" then
        ns.UI:Hide()
    elseif msg == "start" or msg == "queue" or msg == "go" then
        ns.UI:Show(); ns.Queue:Start()
    elseif msg == "stop" then
        ns.Queue:Stop("stopped by /kq")
    elseif msg == "auto" then
        ns.db.autoApply = not ns.db.autoApply
        print("|cff66ccffKeyQueue|r auto-apply: " .. (ns.db.autoApply and "ON" or "OFF"))
        if ns.UI then ns.UI:Refresh() end
    elseif msg == "find" or msg == "listings" then
        ns.db.tab = "listings"; ns.UI:Show()
    elseif msg == "apps" then
        if ns.UI and ns.UI.DumpApps then ns.UI:DumpApps() end
    elseif msg == "raw" then
        if ns.UI and ns.UI.DumpRaw then ns.UI:DumpRaw() end
    elseif msg == "minimap" then
        ns.db.minimapHide = not ns.db.minimapHide
        if ns.UI then ns.UI:UpdateMinimap() end
        print("|cff66ccffKeyQueue|r minimap button: " .. (ns.db.minimapHide and "hidden" or "shown"))
    elseif msg == "debug" then
        if ns.UI and ns.UI.Debug then ns.UI:Debug() end
    else
        ns.UI:Toggle()
    end
end
