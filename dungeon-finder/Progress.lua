local _, ns = ...

-- =========================================================================
-- Progress: which dungeons have you already done at a given key level this season.
-- Drives the "only queue for dungeons I still need" filter, so KeyQueue stops
-- wasting applications on keys you've already completed.
--
--   bestLevel[KEY] - highest COMPLETED key level you have in that dungeon (0 = none)
--   NeededAt(L)    - set of dungeon KEYs whose best is below L (still want an L there)
--
-- Sources (all guarded -- absent/renamed APIs degrade to "everything is needed"):
--   C_ChallengeMode.GetMapTable / GetMapUIInfo - season map IDs + names -> our KEYs
--   C_MythicPlus.GetSeasonBestForMap           - best run per map
--   C_MythicPlus.GetRunHistory                 - season run list (fallback scan)
-- Return shapes have varied across patches, so levels are extracted tolerantly.
-- =========================================================================

local P = {}
ns.Progress = P

P.bestLevel = {}   -- dungeonKey -> best completed level this season
P.mapKey = {}      -- mapID -> dungeonKey
P.keyMap = {}      -- dungeonKey -> mapID
P.loaded = false

local function safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

-- map the season's challenge-mode map IDs to our dungeon KEYs (by name).
function P:BuildMapTable()
    if next(self.mapKey) then return end
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
    local ids = safe(C_ChallengeMode.GetMapTable)
    if type(ids) ~= "table" then return end
    for _, mapID in ipairs(ids) do
        local name = C_ChallengeMode.GetMapUIInfo and (safe(C_ChallengeMode.GetMapUIInfo, mapID))
        local key = name and ns.Dungeons.Match(name)
        if key then
            self.mapKey[mapID] = key
            self.keyMap[key] = mapID
        end
    end
end

-- pull the highest level out of whatever GetSeasonBestForMap returns (number,
-- single table with .level, or an array of affix-score tables).
local function extractLevel(...)
    local lvl = 0
    local function consider(t)
        if type(t) == "number" then
            if t > lvl then lvl = t end
        elseif type(t) == "table" then
            if type(t.level) == "number" and t.level > lvl then lvl = t.level end
            if type(t.bestRunLevel) == "number" and t.bestRunLevel > lvl then lvl = t.bestRunLevel end
            for _, e in ipairs(t) do
                if type(e) == "table" and type(e.level) == "number" and e.level > lvl then lvl = e.level end
            end
        end
    end
    for i = 1, select("#", ...) do consider((select(i, ...))) end
    return lvl
end

function P:Refresh()
    self:BuildMapTable()
    local any = false

    -- per-map season best
    if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
        for key, mapID in pairs(self.keyMap) do
            local lvl = extractLevel(safe(C_MythicPlus.GetSeasonBestForMap, mapID))
            if lvl and lvl > 0 then
                if (self.bestLevel[key] or 0) < lvl then self.bestLevel[key] = lvl end
                any = true
            end
        end
    end

    -- fallback: scan the season's run history for the best completed level per map
    if C_MythicPlus and C_MythicPlus.GetRunHistory then
        local runs = safe(C_MythicPlus.GetRunHistory, true, false)
        if type(runs) == "table" then
            for _, run in ipairs(runs) do
                local mapID = run.mapChallengeModeID or run.challengeModeID or run.mapID
                local key = mapID and self.mapKey[mapID]
                local lvl = run.level or run.keystoneLevel
                local completed = run.completed
                if completed == nil then completed = true end
                if key and type(lvl) == "number" and completed then
                    if (self.bestLevel[key] or 0) < lvl then self.bestLevel[key] = lvl end
                    any = true
                end
            end
        end
    end

    -- every known dungeon gets an explicit 0 so NeededAt is correct before any data
    for _, key in ipairs(ns.Dungeons.order) do
        if self.bestLevel[key] == nil then self.bestLevel[key] = 0 end
    end

    self.loaded = any or self.loaded
    return self.loaded
end

function P:BestLevel(key) return self.bestLevel[key] or 0 end
function P:Loaded() return self.loaded end

-- dungeons whose best completed level is below `level` -> still wanted at that key.
function P:NeededAt(level)
    local set = {}
    for _, key in ipairs(ns.Dungeons.order) do
        if (self.bestLevel[key] or 0) < level then set[key] = true end
    end
    return set
end
