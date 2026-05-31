local _, ns = ...

-- =========================================================================
-- Search: drive the Premade Group Finder search for the seeker side and read the
-- results back as normalized rows. We search the whole Dungeons category and filter
-- to Mythic+ activities client-side -- that sidesteps the unstable shape of the
-- advanced/activity filter args and still reaches every M+ listing.
--
-- NOTE: like KeyComp's Applicants module, the exact C_LFGList.Search signature has
-- drifted across patches, so Kick() tries a few arities. Everything downstream only
-- needs GetSearchResults() to be populated, so a wrong Search arg just means "no
-- results", never a hard error. UNVERIFIED in-client -- expect to confirm live.
-- =========================================================================

local S = {}
ns.Search = S

S.searching = false
S.lastKick = 0
S.category = nil      -- discovered LFG category that holds M+ (fallback 2 = Dungeons)
S.activityMap = nil   -- activityID -> dungeonKey (M+ activities only)
S.mplusSet = nil      -- activityID -> true (is a Mythic+ activity)
S.lastResults = {}

local function gt() return (GetTime and GetTime()) or 0 end

-- is a given activity-info table a Mythic+ one? Prefer the explicit flag; fall back
-- to its name ("Mythic+ ..." / "... Keystone") if the flag isn't present.
local function actIsMplus(act)
    if type(act) ~= "table" then return false end
    if act.isMythicPlusActivity ~= nil then return act.isMythicPlusActivity and true or false end
    local low = (act.fullName or act.shortName or ""):lower()
    return (low:find("mythic+", 1, true) ~= nil) or (low:find("keystone", 1, true) ~= nil)
end

-- find the LFG category that contains Mythic+ activities. Cached only on success,
-- so an early/failed scan retries; otherwise falls back to 2 (Dungeons).
function S:Category()
    if self.category then return self.category end
    if C_LFGList and C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableActivities
        and C_LFGList.GetActivityInfoTable then
        local ok, cats = pcall(C_LFGList.GetAvailableCategories)
        if ok and type(cats) == "table" then
            for _, cat in ipairs(cats) do
                local okA, acts = pcall(C_LFGList.GetAvailableActivities, cat)
                if okA and type(acts) == "table" then
                    for _, aid in ipairs(acts) do
                        local okT, act = pcall(C_LFGList.GetActivityInfoTable, aid)
                        if okT and actIsMplus(act) then
                            self.category = cat
                            return cat
                        end
                    end
                end
            end
        end
    end
    return 2
end

-- Discover which activities are Mythic+ and which dungeon each maps to. Cached once
-- non-empty (activity tables don't change in-session); an empty pass is retried.
function S:DiscoverActivities()
    if self.activityMap then return end
    local map, mplus = {}, {}
    if C_LFGList and C_LFGList.GetActivityInfoTable and C_LFGList.GetAvailableActivities then
        local ok, ids = pcall(C_LFGList.GetAvailableActivities, self:Category())
        if ok and type(ids) == "table" then
            for _, aid in ipairs(ids) do
                local okA, act = pcall(C_LFGList.GetActivityInfoTable, aid)
                if okA and actIsMplus(act) then
                    mplus[aid] = true
                    local key = ns.Dungeons.Match(act.fullName or act.shortName)
                    if key then map[aid] = key end
                end
            end
        end
    end
    if next(mplus) then
        self.activityMap, self.mplusSet = map, mplus
    else
        self.activityMap, self.mplusSet = nil, nil
    end
end

function S:Kick()
    if not (C_LFGList and C_LFGList.Search) then return false end
    if self.searching and (gt() - self.lastKick) < 8 then return false end  -- search in flight
    local cat = self:Category()
    local langs = (C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter()) or nil
    local attempts = {
        function() return C_LFGList.Search(cat, 0, 0, langs) end,
        function() return C_LFGList.Search(cat, 0, 0) end,
        function() return C_LFGList.Search(cat, "", 0, 0, langs) end,
        function() return C_LFGList.Search(cat) end,
    }
    for _, fn in ipairs(attempts) do
        if pcall(fn) then
            self.searching = true
            self.lastKick = gt()
            return true
        end
    end
    return false
end

function S:OnResults()
    self.searching = false
end

-- Resolve an activityID to (dungeonKey, isMythicPlus). Fast path via the cached
-- discovery map; falls back to the activity table directly so a failed or empty
-- discovery pass can't blind the whole addon.
function S:ActivityKey(aid)
    if not aid then return nil, false end
    if self.activityMap and self.activityMap[aid] then return self.activityMap[aid], true end
    if C_LFGList and C_LFGList.GetActivityInfoTable then
        local ok, act = pcall(C_LFGList.GetActivityInfoTable, aid)
        if ok and actIsMplus(act) then
            return ns.Dungeons.Match(act.fullName or act.shortName), true
        end
    end
    if self.mplusSet and self.mplusSet[aid] then return nil, true end
    return nil, false
end

local function memberCounts(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultMemberCounts) then return 0, 0, 0 end
    local ok, c = pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
    if not ok or type(c) ~= "table" then return 0, 0, 0 end
    return c.TANK or 0, c.HEALER or 0, c.DAMAGER or 0
end

-- Pull a keystone level out of a result's text. Builds differ on which field holds
-- the leader's title (e.g. "+19 ..."), so try the known title/description fields,
-- then scan every string field for a strict "+N" -- specific enough not to grab an
-- item level or score by accident.
local KEYSTONE_NUM_FIELDS = {
    "keystoneLevel", "mythicPlusLevel", "keyLevel", "mythicLevel", "activityKeystoneLevel",
}
local function parseKeyFromInfo(info)
    -- 1) a numeric keystone-level field, if this build exposes one. The client renders
    --    "+19" from a number like this, so it won't appear in any text field.
    for _, fk in ipairs(KEYSTONE_NUM_FIELDS) do
        local v = info[fk]
        if type(v) == "number" and v >= 2 and v <= 50 then return v end
    end
    -- 2) the leader's title / description text ("+19 ...").
    local function tryFields(...)
        for i = 1, select("#", ...) do
            local k = ns.Dungeons.ParseKey((select(i, ...)))
            if k then return k end
        end
    end
    local k = tryFields(info.name, info.title, info.comment, info.description)
    if k then return k end
    -- 3) any string field containing a strict "+N".
    for _, v in pairs(info) do
        if type(v) == "string" then
            local n = v:match("%+%s*(%d+)")
            n = n and tonumber(n)
            if n and n >= 2 and n <= 50 then return n end
        end
    end
    return nil
end

-- one search result -> a flat row the filter/UI can use. Role openness assumes the
-- standard 1 tank / 1 healer / 3 dps dungeon composition.
function S:Normalize(resultID, info, key)
    local aid = info.activityID or (info.activityIDs and info.activityIDs[1])
    local tank, heal, dps = memberCounts(resultID)
    local keyLevel = parseKeyFromInfo(info)
    return {
        resultID      = resultID,
        activityID    = aid,
        dungeonKey    = key,
        abbr          = (key and ns.Dungeons.list[key].abbr) or "M+",
        dungeonName   = (key and ns.Dungeons.list[key].name) or (info.name) or "Mythic+",
        keyLevel      = keyLevel,
        leaderName    = info.leaderName,
        leaderScore   = info.leaderOverallDungeonScore or 0,
        requiredScore = info.requiredDungeonScore or 0,
        numMembers    = info.numMembers or (tank + heal + dps),
        tank = tank, heal = heal, dps = dps,
        tankOpen = tank < 1, healOpen = heal < 1, dpsOpen = dps < 3,
        ageSeconds    = info.age or 0,
        comment       = info.comment or "",
        name          = info.name or "",
    }
end

-- read the current result set, keeping only Mythic+ listings.
function S:Read()
    local out = {}
    if not (C_LFGList and C_LFGList.GetSearchResults and C_LFGList.GetSearchResultInfo) then
        self.lastResults = out
        return out
    end
    self:DiscoverActivities()
    local a, b = C_LFGList.GetSearchResults()
    local results = (type(a) == "table" and a) or (type(b) == "table" and b) or nil
    if type(results) ~= "table" then self.lastResults = out; return out end
    for _, resultID in ipairs(results) do
        local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
        if ok and type(info) == "table" and not info.isDelisted then
            local aid = info.activityID or (info.activityIDs and info.activityIDs[1])
            local key, isM = self:ActivityKey(aid)
            -- Include if the activity says M+ OR the listing has a parseable keystone
            -- ("+18 resi", "+19 ..."). The isMythicPlusActivity flag is unreliable and
            -- was wrongly excluding real M+ listings; a "+N" title is a definitive
            -- M+ signal, and key-less (heroic/normal) listings get filtered out later.
            if isM or parseKeyFromInfo(info) then
                out[#out + 1] = self:Normalize(resultID, info, key)
            end
        end
    end
    self.lastResults = out
    return out
end
