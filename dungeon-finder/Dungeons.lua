local _, ns = ...

-- =========================================================================
-- Dungeons: the 8 Midnight S1 Mythic+ dungeons (same keys/names as KeyComp so
-- the two addons speak the same dungeon identities), plus the text utilities the
-- seeker side needs:
--   Match(text)    - fuzzy-match a Blizzard activity/instance/map name -> our KEY
--   ParseKey(text) - pull a keystone level ("+19") out of a listing title/comment
-- Keystone level is NOT cleanly exposed per search result, so listings are parsed
-- for "+N" the same way the in-game UI shows it (and the way PGF-style addons do).
-- =========================================================================

local D = {}
ns.Dungeons = D

D.order = {
    "MAGISTERS_TERRACE",
    "MAISARA_CAVERNS",
    "WINDRUNNER_SPIRE",
    "NEXUS_POINT_XENAS",
    "PIT_OF_SARON",
    "SEAT_OF_THE_TRIUMVIRATE",
    "SKYREACH",
    "ALGETHAR_ACADEMY",
}

D.list = {
    MAGISTERS_TERRACE       = { name = "Magister's Terrace",      abbr = "MT" },
    MAISARA_CAVERNS         = { name = "Maisara Caverns",         abbr = "MC" },
    WINDRUNNER_SPIRE        = { name = "Windrunner Spire",        abbr = "WS" },
    NEXUS_POINT_XENAS       = { name = "Nexus-Point Xenas",       abbr = "NPX" },
    PIT_OF_SARON            = { name = "Pit of Saron",            abbr = "PoS" },
    SEAT_OF_THE_TRIUMVIRATE = { name = "Seat of the Triumvirate", abbr = "SotT" },
    SKYREACH                = { name = "Skyreach",                abbr = "Sky" },
    ALGETHAR_ACADEMY        = { name = "Algeth'ar Academy",       abbr = "AA" },
}

-- Normalize a name for matching: lowercase, strip everything but a-z0-9. Blizzard's
-- activity/instance strings rarely match our hand-entered names exactly (apostrophe
-- placement, prefixes like "Mythic+", punctuation), so compare on the normal form.
local function normName(s)
    if type(s) ~= "string" then return "" end
    return (s:lower():gsub("[^%w]", ""))
end
D.normName = normName

-- Blizzard label (activity fullName / instance name / map name) -> dungeon KEY.
function D.Match(label)
    local nl = normName(label)
    if nl == "" then return nil end
    for _, key in ipairs(D.order) do
        local dn = normName(D.list[key].name)
        if dn ~= "" and (nl == dn or nl:find(dn, 1, true)) then return key end
    end
    return nil
end

-- Extract a keystone level from a listing's title/comment. Prefer the "+N" / "N+"
-- forms players actually type; fall back to "key N" / "lvl N"; last resort a lone
-- 1-2 digit number in M+ range. Returns nil if nothing plausible is found.
function D.ParseKey(s)
    if type(s) ~= "string" or s == "" then return nil end
    -- strip WoW UI escape sequences (color |cXXXXXXXX..|r, texture |T..|t, link
    -- |H..|h, atlas |A..|a) that can wrap a listing title and break the match.
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
         :gsub("|T.-|t", ""):gsub("|H.-|h", ""):gsub("|A.-|a", "")
    -- Only explicit keystone forms. NO bare-number fallback -- "Need 2 dps" must not
    -- read as a +2 key (that false-positive let heroic listings into the M+ set).
    local n = s:match("^%s*%+%s*(%d+)")   -- leading "+19" (the common title form)
        or s:match("%+%s*(%d+)")           -- "+19" anywhere (incl. "Mythic+ 19")
        or s:match("(%d+)%s*%+")           -- "19+"
        or s:match("[Kk][Ee][Yy]%s*(%d+)")
        or s:match("[Ll][Vv][Ll]%s*(%d+)")
        or s:match("[Ll][Ee][Vv][Ee][Ll]%s*(%d+)")
        or s:match("^%s*(%d+)")            -- leading bare number ("19 MT", "11 resi")
    -- the 2..50 range below guards bare numbers (ilvl 639 / io 2900 fall outside).
    n = tonumber(n)
    if n and n >= 2 and n <= 50 then return n end
    return nil
end
