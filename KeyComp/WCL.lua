local _, ns = ...

-- =========================================================================
-- WCL: look up an applicant's baked Warcraft Logs M+ data.
--
-- The data table (ns.WCLData / global KeyCompWCL) is generated externally by
-- tools/wcl_build.py and shipped in Data/WCLData.lua. It is keyed:
--     chars[REGION][normalizedKey] = {
--         n, rl, cl, sp,           -- name, realm, classFile, spec
--         bk, bs,                  -- best key level, best run score (across dungeons)
--         d = { DUNGEONKEY = { k=keylevel, dps=, sc=score, md="g|s|b|" } }
--     }
--
-- normalizedKey MUST match tools/wcl_build.py norm(): strip spaces / straight
-- and curly apostrophes / hyphens, then ASCII-only lowercase. Realm matching is
-- best-effort for v1 (no realm-slug table yet).
-- =========================================================================

local W = {}
ns.WCL = W

local function data()
    return ns.WCLData or KeyCompWCL
end

function W:IsLoaded()
    local d = data()
    return d and d.chars and true or false
end

function W:Generated()
    local d = data()
    return d and d.generated or nil
end

-- ASCII-only lowercase ([A-Z] is locale-independent, mirroring the builder).
local function asciiLower(s)
    return (s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

local function norm(s)
    if not s then return "" end
    s = s:gsub("\226\128\153", "")  -- curly apostrophe U+2019 (3-byte UTF-8)
    s = s:gsub("[ '%-]", "")        -- space, straight apostrophe, hyphen
    return asciiLower(s)
end
W.norm = norm

-- in-game region -> WCL region code. Prefer the portal CVar (string), fall back
-- to GetCurrentRegion() numbering (1=US 2=KR 3=EU 4=TW 5=CN).
local NUM_REGION = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }
local VALID_REGION = { US = true, EU = true, KR = true, TW = true, CN = true }
function W:PlayerRegion()
    local portal = GetCVar and GetCVar("portal")
    if portal then
        local up = portal:upper()
        if VALID_REGION[up] then return up end
    end
    if GetCurrentRegion then
        local r = NUM_REGION[GetCurrentRegion()]
        if r then return r end
    end
    return nil
end

local function playerRealm()
    if GetNormalizedRealmName then
        local r = GetNormalizedRealmName()
        if r and r ~= "" then return r end
    end
    return (GetRealmName and GetRealmName()) or ""
end

-- Split an in-game "Name-Realm" (realm omitted for same-realm). Character names
-- never contain "-", so the first hyphen separates name from realm (realm names
-- may themselves contain hyphens, e.g. Azjol-Nerub -> normalised away anyway).
local function splitNameRealm(full)
    if not full or full == "" then return nil, nil end
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    if name then return name, realm end
    return full, playerRealm()
end

-- Look up by in-game full name (optionally pass an explicit region). Returns the
-- record table or nil.
function W:Lookup(full, region)
    if not self:IsLoaded() then return nil end
    local name, realm = splitNameRealm(full)
    if not name then return nil end
    local key = norm(name) .. "-" .. norm(realm)
    local chars = data().chars

    region = region or self:PlayerRegion()
    if region and chars[region] then
        local rec = chars[region][key]
        if rec then return rec, region end
    end
    -- region unknown / no hit: scan every shipped region as a fallback
    for reg, bucket in pairs(chars) do
        if reg ~= region then
            local rec = bucket[key]
            if rec then return rec, reg end
        end
    end
    return nil
end

-- Per-dungeon stat subtable for a record, or nil.
function W:DungeonStat(rec, dungeonKey)
    return rec and rec.d and dungeonKey and rec.d[dungeonKey] or nil
end

-- The character's highest-key logged run across all dungeons:
-- { dungeon = key, k, dps, sc, md } or nil. Tie-broken by higher dps.
function W:BestEntry(rec)
    if not (rec and rec.d) then return nil end
    local best, bestDk
    for dk, s in pairs(rec.d) do
        if not best or (s.k or 0) > (best.k or 0)
            or ((s.k or 0) == (best.k or 0) and (s.dps or 0) > (best.dps or 0)) then
            best, bestDk = s, dk
        end
    end
    if not best then return nil end
    return { dungeon = bestDk, k = best.k, dps = best.dps, sc = best.sc, md = best.md }
end

-- ---------------------------------------------------------------- format ----
function W.FmtDps(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000 then return string.format("%dk", math.floor(n / 1000 + 0.5)) end
    return tostring(n)
end

local MEDAL_COLOR = { g = "ffffd100", s = "ffc7c7cf", b = "ffcd7f32" }
function W.MedalText(md)
    if not md or md == "" then return "" end
    local c = MEDAL_COLOR[md] or "ffffffff"
    local label = (md == "g" and "Gold") or (md == "s" and "Silver") or (md == "b" and "Bronze") or md
    return "|c" .. c .. label .. "|r"
end

-- "3d" / "14h" / "now" — age of the baked data, for an in-UI freshness hint.
function W:AgeText()
    local g = self:Generated()
    if not g then return "no data" end
    local secs = (time and time() or 0) - g
    if secs < 0 then secs = 0 end
    if secs < 3600 then return "<1h old" end
    if secs < 86400 then return math.floor(secs / 3600) .. "h old" end
    return math.floor(secs / 86400) .. "d old"
end
