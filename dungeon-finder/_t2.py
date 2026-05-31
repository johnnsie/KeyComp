#!/usr/bin/env python3
# KeyQueue end-to-end verification harness.
#
# WoW ships Lua 5.1; we have no Lua interpreter on the dev box, only lupa (Lua 5.4/5.5).
# That's fine for syntax + logic: this loads the REAL .lua modules under a mock WoW API,
# fires the load/login events, then drives the search -> filter -> queue pipeline with
# realistic Premade Group Finder data and asserts the outcomes.
#
#   python _t2.py        # run all checks; exit 1 if any FAIL
#
# Mocks live in HARNESS (Lua). Module sources are read as raw bytes and handed to Lua's
# load() so the byte-escapes in the .lua (e.g. "\226\156\147") survive untouched.

import os
import sys
import lupa

BASE = os.path.dirname(os.path.abspath(__file__))
ORDER = ["Dungeons.lua", "Progress.lua", "Search.lua",
         "Filter.lua", "Queue.lua", "Core.lua", "UI.lua"]

HARNESS = r'''
-- ============================ test bookkeeping ============================
local PASS, FAIL, LINES = 0, 0, {}
local function check(name, cond, extra)
  if cond then
    PASS = PASS + 1
    LINES[#LINES + 1] = "  ok   " .. name
  else
    FAIL = FAIL + 1
    LINES[#LINES + 1] = "X FAIL " .. name .. (extra and ("   [" .. tostring(extra) .. "]") or "")
  end
end
local function eq(name, got, want)
  check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ============================ mock WoW API ===============================
local CLOCK = { t = 1000 }
local TIMERS = {}
local PRINTLOG = {}

local realprint = print
function print(...)
  local p = {}
  for i = 1, select("#", ...) do p[#p + 1] = tostring((select(i, ...))) end
  PRINTLOG[#PRINTLOG + 1] = table.concat(p, " ")
end

-- universal frame/region stub: every unknown method is a chainable no-op; a handful
-- return real numbers/booleans/children so the UI layout + event code can run.
local newStub
local NUMRET = { GetHeight = 1080, GetWidth = 140, GetVerticalScroll = 0, GetStringHeight = 12,
                 GetLeft = 200, GetTop = 600, GetEffectiveScale = 1, GetScale = 1, GetAlpha = 1,
                 GetNumPoints = 0 }
local function stubMethod(key)
  return function(self, ...)
    if key == "Show" then self.__shown = true; return self end
    if key == "Hide" then self.__shown = false; return self end
    if key == "IsShown" or key == "IsVisible" then return self.__shown and true or false end
    if key == "SetText" then self.__text = (...); return self end
    if key == "GetText" then return self.__text or "" end
    if key == "SetChecked" then self.__checked = (...) and true or false; return self end
    if key == "GetChecked" then return self.__checked and true or false end
    if key == "SetValue" then self.__value = (...); return self end
    if key == "GetValue" then return self.__value or 1 end
    if key == "HasFocus" then return false end
    if key == "SetScript" then local n, fn = ...; self._scripts[n] = fn; return self end
    if key == "HookScript" then local n, fn = ...; self._scripts[n] = fn; return self end
    if key == "GetScript" then return self._scripts[(...)] end
    if key == "RegisterEvent" then self.__events = self.__events or {}; self.__events[(...)] = true; return self end
    if key == "CreateTexture" then return newStub("texture") end
    if key == "CreateFontString" then return newStub("fontstring") end
    if key == "CreateAnimationGroup" then return newStub("animgroup") end
    if key == "GetThumbTexture" then return newStub("texture") end
    if key == "GetCenter" then return 70, 70 end
    if NUMRET[key] ~= nil then return NUMRET[key] end
    return self
  end
end
local STUB_MT = { __index = function(_, k) return stubMethod(k) end }
newStub = function(kind)
  return setmetatable({ __stub = true, __kind = kind, _scripts = {}, __shown = false }, STUB_MT)
end

function CreateFrame(ftype, name, parent, template) return newStub(ftype or "frame") end
UIParent = newStub("UIParent")
Minimap = newStub("Minimap")
GameTooltip = newStub("GameTooltip")
RaidWarningFrame = newStub("RaidWarningFrame")
ChatTypeInfo = { RAID_WARNING = {} }
GetCursorPosition = function() return 100, 100 end
IsMouseButtonDown = function() return false end

C_Timer = {
  NewTicker = function(sec, fn) TICKERFN = fn; return newStub("ticker") end,
  After     = function(sec, fn) TIMERS[#TIMERS + 1] = fn; return newStub("timer") end,
}
local function RUNTIMERS()
  local t = TIMERS; TIMERS = {}
  for _, fn in ipairs(t) do
    local ok, err = pcall(fn)
    if not ok then PRINTLOG[#PRINTLOG + 1] = "TIMER ERROR: " .. tostring(err) end
  end
end

function GetTime() return CLOCK.t end
function GetSpecialization() return 1 end
function GetSpecializationInfo(i) return 256, "Discipline", "d", "icon", "HEALER" end
function GetNumGroupMembers() return GROUPN or 0 end
function InCombatLockdown() return INCOMBAT or false end
SOUNDKIT = { READY_CHECK = 8960 }
SOUND = { played = false }
function PlaySound(...) SOUND.played = true end
function RaidNotice_AddMessage(...) end
SENT = { n = 0 }
function SendChatMessage(...) SENT.n = SENT.n + 1 end
function date(fmt) return "12:00:00" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SlashCmdList = {}   -- the client always provides this global; the addon indexes into it
DOSEARCHED = false
LFGListFrame = { SearchPanel = newStub("searchpanel") }   -- the live Group Finder search panel
function LFGListSearchPanel_DoSearch(panel) DOSEARCHED = true end  -- re-runs the user's search

-- ----- C_LFGList (search + apply) with rewritable per-scenario data -----
local LFG = {
  cats = { 1, 2, 3 },
  acts = { [1] = { 9001 }, [2] = { 2001, 2002, 2003 }, [3] = {} },
  actInfo = {
    [9001] = { fullName = "Heroic Dungeon",      isMythicPlusActivity = false },
    [2001] = { fullName = "Algeth'ar Academy",   isMythicPlusActivity = true },
    [2002] = { fullName = "Skyreach",            isMythicPlusActivity = true },
    [2003] = { fullName = "Pit of Saron",        isMythicPlusActivity = true },
  },
  results = {}, info = {}, counts = {}, apps = {}, appInfo = {},
}
C_LFGList = {
  GetAvailableCategories       = function() return LFG.cats end,
  GetAvailableActivities       = function(cat) return LFG.acts[cat] or {} end,
  GetActivityInfoTable         = function(aid) return LFG.actInfo[aid] end,
  GetSearchResults             = function() return LFG.results end,
  GetSearchResultInfo          = function(rid) return LFG.info[rid] end,
  GetSearchResultMemberCounts  = function(rid) return LFG.counts[rid] end,
  GetLanguageSearchFilter      = function() return nil end,
  HasActiveEntry               = function() return ACTIVEENTRY or false end,
  Search                       = function() LFG.searched = true; return true end,
  GetApplications              = function() return LFG.apps end,
  GetApplicationInfo           = function(appID) return LFG.appInfo[appID] end,
  ApplyToGroup = function(rid, t, h, d)
    local present = false
    for _, a in ipairs(LFG.apps) do if a == rid then present = true end end
    if not present then LFG.apps[#LFG.apps + 1] = rid end
    LFG.appInfo[rid] = { searchResultID = rid, applicationStatus = "applied" }
    return true
  end,
}
-- set the live listing set for a scenario. rows: {rid, aid, name, comment, leader,
-- members={T,H,D}, score, req, age, num, delisted}
local function setResults(rows)
  LFG.results, LFG.info, LFG.counts, LFG.apps, LFG.appInfo = {}, {}, {}, {}, {}
  for _, r in ipairs(rows) do
    LFG.results[#LFG.results + 1] = r.rid
    LFG.info[r.rid] = {
      activityID = r.aid, name = r.name, comment = r.comment or "",
      leaderName = r.leader, leaderOverallDungeonScore = r.score or 0,
      requiredDungeonScore = r.req or 0, age = r.age or 0,
      numMembers = r.num, isDelisted = r.delisted or false,
      leaderDungeonScoreInfo = r.best and { bestRunLevel = r.best, mapScore = r.best * 125 } or nil,
    }
    LFG.counts[r.rid] = { TANK = r.members[1], HEALER = r.members[2], DAMAGER = r.members[3] }
  end
end

C_ChallengeMode = {
  GetMapTable            = function() return { 501, 502, 503 } end,
  GetMapUIInfo           = function(id)
    return ({ [501] = "Algeth'ar Academy", [502] = "Skyreach", [503] = "Pit of Saron" })[id]
  end,
  GetOverallDungeonScore = function() return 3712 end,
}
C_MythicPlus = {
  GetSeasonBestForMap = function(mapID)
    if mapID == 501 then return { { level = 20 }, { level = 18 } } end
    return nil
  end,
  GetRunHistory = function() return { { mapChallengeModeID = 502, level = 17, completed = true } } end,
}
C_PlayerInfo = { GetPlayerMythicPlusRatingSummary = function() return { currentSeasonScore = 3712 } end }

-- ============================ load the addon =============================
local ORDER_LUA = { "Dungeons.lua", "Progress.lua", "Search.lua",
                    "Filter.lua", "Queue.lua", "Core.lua", "UI.lua" }
local ns = {}
for _, name in ipairs(ORDER_LUA) do
  local chunk, err = load(MODS[name], "@" .. name)
  check("compile " .. name, chunk ~= nil, err)
  if chunk then
    local ok, e = pcall(chunk, "dungeon-finder", ns)
    check("run " .. name, ok, e)
  end
end

local f = ns.eventFrame
local function fire(ev, a1)
  if f and f._scripts.OnEvent then f._scripts.OnEvent(f, ev, a1) end
end
check("event frame created", f ~= nil)
do
  local ok, e = pcall(fire, "ADDON_LOADED", "dungeon-finder")
  check("ADDON_LOADED ok", ok, e)
end
do
  local ok, e = pcall(fire, "PLAYER_LOGIN")
  check("PLAYER_LOGIN ok (UI:Init + Show + Refresh)", ok, e)
end

-- ============================ scenario runner ============================
local function scenario(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    FAIL = FAIL + 1
    LINES[#LINES + 1] = "X FAIL [scenario crashed] " .. name .. "   [" .. tostring(err) .. "]"
  end
end

local D = ns.Dungeons
local P = ns.Progress
local S = ns.Search
local Filter = ns.Filter
local Q = ns.Queue

-- force progress to a known state (override the API-derived values)
local function setBest(tbl)
  for _, k in ipairs(D.order) do P.bestLevel[k] = tbl[k] or 0 end
  P.loaded = true
end
local function allNeeded() setBest({}) end  -- every dungeon best 0 -> all needed at +19

-- -------------------------------- Core/db --------------------------------
scenario("Core defaults", function()
  eq("db.targetKey default 19", ns.db.targetKey, 19)
  eq("db.keyMax default 19", ns.db.keyMax, 19)
  eq("db.autoApply default OFF", ns.db.autoApply, false)
  eq("db.autoTargets default ON", ns.db.autoTargets, true)
  eq("db.useOwnSearch default OFF", ns.db.useOwnSearch, false)
  eq("db.autoRefresh default ON", ns.db.autoRefresh, true)
  eq("Filter:Role -> HEALER (Disc)", Filter:Role(), "HEALER")
end)

scenario("Search reads leader's best-run level (PGF-style key proxy)", function()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", score = 3500, best = 21, age = 30, num = 4, members = { 1, 0, 3 } } })
  local r = S:Read()[1]
  eq("leaderBest from leaderDungeonScoreInfo.bestRunLevel", r and r.leaderBest, 21)
  check("mapScore read too", r and r.mapScore and r.mapScore > 0)
end)

scenario("Auto-refresh re-runs your Group Finder search", function()
  eq("autoRefresh default ON", ns.db.autoRefresh, true)
  DOSEARCHED = false
  S.lastRefresh = 0
  local ok = S:Refresh(true)
  check("Refresh triggered a search", ok == true)
  check("preferred path re-runs YOUR search (preserves the +19 filter)", DOSEARCHED == true)
end)

-- -------------------------------- Dungeons -------------------------------
scenario("Dungeons.Match", function()
  eq("Match exact", D.Match("Algeth'ar Academy"), "ALGETHAR_ACADEMY")
  eq("Match normalized", D.Match("algetharacademy"), "ALGETHAR_ACADEMY")
  eq("Match with prefix", D.Match("Mythic+ Skyreach"), "SKYREACH")
  eq("Match unknown -> nil", D.Match("Random Battleground"), nil)
  eq("Match empty -> nil", D.Match(""), nil)
end)

scenario("Dungeons.ParseKey", function()
  eq("'+19 resi'", D.ParseKey("+19 resi"), 19)
  eq("'Mythic+ 18'", D.ParseKey("Mythic+ 18"), 18)
  eq("'19+'", D.ParseKey("19+"), 19)
  eq("'key 12'", D.ParseKey("key 12"), 12)
  eq("'Need 2 dps' (no false +2)", D.ParseKey("Need 2 dps"), nil)
  eq("'ilvl 639' (range guard)", D.ParseKey("ilvl 639"), nil)
  eq("io '2900 io' out of range", D.ParseKey("done 2900 io"), nil)
  eq("color-escaped '+19'", D.ParseKey("|cffff0000+19|r Algeth"), 19)
  eq("'+99' out of range", D.ParseKey("+99"), nil)
  eq("leading bare '19 MT'", D.ParseKey("19 MT"), 19)
end)

-- -------------------------------- Progress -------------------------------
scenario("Progress.Refresh from API", function()
  P.bestLevel = {}; P.mapKey = {}; P.keyMap = {}; P.loaded = false
  P:Refresh()
  eq("AA season best 20 (affix array)", P:BestLevel("ALGETHAR_ACADEMY"), 20)
  eq("Skyreach best 17 (run history)", P:BestLevel("SKYREACH"), 17)
  eq("PoS best 0", P:BestLevel("PIT_OF_SARON"), 0)
  check("progress loaded", P:Loaded())
  local need = P:NeededAt(19)
  eq("AA not needed at +19 (done 20)", need["ALGETHAR_ACADEMY"], nil)
  eq("Skyreach needed at +19 (17<19)", need["SKYREACH"], true)
  eq("needed count = 7 (all but AA)", count(need), 7)
end)

-- -------------------------------- Search ---------------------------------
scenario("Search discovery + Read", function()
  eq("Category finds M+ cat (2)", S:Category(), 2)
  S.activityMap = nil; S.mplusSet = nil
  S:DiscoverActivities()
  eq("3 M+ activities discovered", count(S.mplusSet), 3)
  eq("activity 2001 -> AA", S.activityMap[2001], "ALGETHAR_ACADEMY")

  setResults({
    { rid = 1, aid = 2001, name = "+19 AA LF heal",  leader = "Tank1", score = 3500, age = 30, num = 4, members = { 1, 0, 3 } },
    { rid = 2, aid = 2002, name = "+18 sky",          leader = "L2",    age = 10,            members = { 1, 0, 2 } },
    { rid = 3, aid = 9001, name = "+19 PoS gogo",     leader = "L3",    age = 5,             members = { 0, 0, 2 } },  -- non-M+ activity, +N title
    { rid = 4, aid = 9001, name = "Need 2 dps heroic",leader = "L4",                         members = { 0, 0, 3 } },  -- non-M+, no key -> excluded
    { rid = 5, aid = 2003, name = "+19 PoS",          leader = "L5", delisted = true,        members = { 1, 0, 2 } },  -- delisted -> excluded
  })
  local res = S:Read()
  eq("Read keeps M+ and +N-title listings, drops no-key-non-M+ and delisted", #res, 3)
  -- find the rid3 row (non-M+ activity, parsed from title)
  local byRid = {}
  for _, r in ipairs(res) do byRid[r.resultID] = r end
  check("rid1 present", byRid[1] ~= nil)
  check("rid3 (title-parsed +19, unmapped dungeon) present", byRid[3] ~= nil)
  eq("rid3 keyLevel parsed 19", byRid[3] and byRid[3].keyLevel, 19)
  eq("rid3 dungeonKey unmapped (nil)", byRid[3] and byRid[3].dungeonKey, nil)
  eq("rid4 (no key) absent", byRid[4], nil)
  eq("rid5 (delisted) absent", byRid[5], nil)
  eq("rid1 healOpen", byRid[1] and byRid[1].healOpen, true)
end)

-- -------------------------------- Filter ---------------------------------
scenario("Filter match + rank", function()
  allNeeded()
  setResults({
    { rid = 1, aid = 2001, name = "+19 AA LF heal", leader = "Tank1", score = 3500, req = 0,    age = 30, num = 4, members = { 1, 0, 3 } },  -- MATCH
    { rid = 2, aid = 2002, name = "+18 sky",         leader = "L2",                              age = 10,         members = { 1, 0, 2 } },  -- key (out of range)
    { rid = 3, aid = 9001, name = "+19 PoS gogo",    leader = "L3",   score = 0,                 age = 5,          members = { 0, 0, 2 } },  -- MATCH (unmapped)
    { rid = 6, aid = 2001, name = "+19 AA full",     leader = "L6",                              age = 20,         members = { 1, 1, 3 } },  -- no-slot
    { rid = 7, aid = 2002, name = "+19 sky gated",   leader = "L7",   req = 4000,                age = 15,         members = { 1, 0, 2 } },  -- gated (req>my 3712)
  })
  local c = Filter:Criteria()
  eq("criteria minKey 19", c.minKey, 19)
  eq("criteria role HEALER", c.role, "HEALER")
  local matched, reasons = Filter:Evaluate(S:Read(), c, Q:Ctx())
  eq("2 listings match", #matched, 2)
  eq("drop: out-of-range key", reasons["key"], 1)
  eq("drop: no healer slot", reasons["no-slot"], 1)
  eq("drop: rating-gated", reasons["gated"], 1)
  eq("best match ranked first = rid1 (near-full, fresh, exact)", matched[1] and matched[1].resultID, 1)
end)

scenario("Filter gating needs known score only", function()
  allNeeded()
  setResults({
    { rid = 7, aid = 2002, name = "+19 sky gated", leader = "L7", req = 4000, age = 15, members = { 1, 0, 2 } },
  })
  local c = Filter:Criteria()
  -- with known score 3712 < 4000 -> gated
  local m1 = Filter:Evaluate(S:Read(), c, { myScore = 3712, blacklist = {} })
  eq("gated when score known", #m1, 0)
  -- with unknown score (0) -> must NOT silently filter the gated listing
  local m2 = Filter:Evaluate(S:Read(), c, { myScore = 0, blacklist = {} })
  eq("kept when score unknown", #m2, 1)
end)

scenario("Filter dungeon-done exclusion + all-done fallback", function()
  -- AA done at 19 -> rid1 (AA) excluded; rid3 (unmapped) still matches
  setBest({ ALGETHAR_ACADEMY = 19 })
  setResults({
    { rid = 1, aid = 2001, name = "+19 AA",      leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } },
    { rid = 3, aid = 9001, name = "+19 PoS gogo", leader = "L3",    age = 5,          members = { 0, 0, 2 } },
  })
  local matched, reasons = Filter:Evaluate(S:Read(), Filter:Criteria(), Q:Ctx())
  eq("AA dropped as done", reasons["dungeon-done"], 1)
  eq("unmapped +19 still matches", #matched, 1)

  -- all dungeons done -> NeededAt empty -> criteria.dungeons falls back to nil (all)
  setBest({ MAGISTERS_TERRACE = 30, MAISARA_CAVERNS = 30, WINDRUNNER_SPIRE = 30,
            NEXUS_POINT_XENAS = 30, PIT_OF_SARON = 30, SEAT_OF_THE_TRIUMVIRATE = 30,
            SKYREACH = 30, ALGETHAR_ACADEMY = 30 })
  local c = Filter:Criteria()
  eq("all-done -> dungeons = nil (show all)", c.dungeons, nil)
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  local m = Filter:Evaluate(S:Read(), c, Q:Ctx())
  eq("farmer still sees +19 when all done", #m, 1)
end)

scenario("Filter blacklist exclusion", function()
  allNeeded()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  local ctx = { myScore = 3712, blacklist = { Tank1 = GetTime() + 600 } }
  local matched, reasons = Filter:Evaluate(S:Read(), Filter:Criteria(), ctx)
  eq("blacklisted leader dropped", reasons["blacklist"], 1)
  eq("nothing matches", #matched, 0)
end)

-- the in-client screenshot showed an unreadable "+nil" PoS listing. It MUST still be
-- shown (hiding all key-less groups left the Listings empty, since many titles lack
-- "+N"), but it must NOT be apply-eligible by default -- that was the +12 path.
scenario("Filter KEEPS unreadable-key listings; the apply gate protects", function()
  allNeeded()
  setResults({
    { rid = 1, aid = 2001, name = "+19 AA",            leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } }, -- readable +19
    { rid = 9, aid = 2003, name = "LF heal Madskiller", leader = "Mad",   age = 10,         members = { 1, 0, 3 } }, -- PoS, no +N -> +nil
  })
  ns.db.includeUnknownKey = false
  local matched = Filter:Evaluate(S:Read(), Filter:Criteria(), Q:Ctx())
  eq("both listings are shown (readable + unreadable)", #matched, 2)
  local elig = 0
  for _, r in ipairs(matched) do if Q:Eligible(r) then elig = elig + 1 end end
  eq("only the readable +19 is apply-eligible", elig, 1)
  ns.db.includeUnknownKey = true
  elig = 0
  for _, r in ipairs(matched) do if Q:Eligible(r) then elig = elig + 1 end end
  eq("toggle on -> both eligible", elig, 2)
  ns.db.includeUnknownKey = false
end)

-- -------------------------------- Queue ----------------------------------
local function resetQueue()
  Q:Stop("test reset"); Q.active = false
  Q.applied = {}; Q.leaderOf = {}; Q.blacklist = {}; Q.invitedBy = nil
  Q.stats = { searched = 0, matched = 0, applied = 0, declined = 0, invited = 0 }
  SOUND.played = false
end

scenario("Queue ApplyNext fires confirmed applies", function()
  resetQueue(); allNeeded()
  setResults({
    { rid = 1, aid = 2001, name = "+19 AA",      leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } },
    { rid = 3, aid = 9001, name = "+19 PoS gogo", leader = "L3",    age = 5,          members = { 0, 0, 2 } },
  })
  local fired = Q:ApplyNext()
  RUNTIMERS()  -- fire the ~1s "confirm pending" callbacks
  check("ApplyNext reports it fired", fired == true)
  check("ApplyNext armed the queue", Q.active == true)
  eq("pending = 2", Q:Pending(), 2)
  eq("stats.applied = 2 (confirmed)", Q.stats.applied, 2)
end)

scenario("Queue ApplyNext is STRICT on unreadable key", function()
  resetQueue(); allNeeded()
  -- a real M+ listing whose title has no +N -> Filter keeps it, but ApplyNext skips it
  setResults({ { rid = 8, aid = 2001, name = "LF healer keystone", leader = "L8", age = 5, members = { 1, 0, 3 } } })
  ns.db.includeUnknownKey = false
  local fired = Q:ApplyNext()
  RUNTIMERS()
  eq("no auto-apply to unreadable key", Q.stats.applied, 0)
  check("ApplyNext returns false (nothing fired)", fired == false)
  -- with the opt-in toggle on, it applies
  resetQueue()
  ns.db.includeUnknownKey = true
  Q:ApplyNext(); RUNTIMERS()
  eq("includeUnknownKey -> applied 1", Q.stats.applied, 1)
  ns.db.includeUnknownKey = false
end)

scenario("Row-Apply = manual override (allows +?); one-tap stays strict", function()
  resetQueue(); allNeeded()
  ns.db.includeUnknownKey = false
  -- a real M+ listing whose key we can't read ("+?")
  setResults({ { rid = 8, aid = 2001, name = "LF healer keystone", leader = "L8", age = 5, members = { 1, 0, 3 } } })
  S:Read()
  local r = ns.Search.lastResults[1]
  check("row has unreadable key", r.keyLevel == nil)
  eq("one-tap (Eligible) still refuses +?", Q:Eligible(r), false)
  local ok = Q:ApplyManual(r); RUNTIMERS()
  check("manual row-Apply DOES apply to +? (your call)", ok == true)
  eq("manual +? applied", Q.stats.applied, 1)
  -- a readable in-range +19 applies via row too
  resetQueue()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  S:Read()
  Q:ApplyManual(ns.Search.lastResults[1]); RUNTIMERS()
  eq("readable +19 applied via row", Q.stats.applied, 1)
  -- but a readable key OUTSIDE your range is refused even on a manual click
  resetQueue()
  setResults({ { rid = 2, aid = 2002, name = "+12 sky", leader = "L2", age = 5, members = { 1, 0, 2 } } })
  S:Read()
  local r3 = ns.Search.lastResults[1]
  eq("parsed +12", r3.keyLevel, 12)
  local ok3 = Q:ApplyManual(r3); RUNTIMERS()
  check("manual refuses readable out-of-range +12", ok3 == false)
  eq("nothing applied for +12", Q.stats.applied, 0)
end)

scenario("Queue invite = HOLD (alarm once, no stop, one-tap paused)", function()
  resetQueue(); allNeeded()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  Q:Start()
  Q:ApplyNext(); RUNTIMERS()
  LFG.appInfo[1].applicationStatus = "invited"
  Q:Sync()
  eq("invitedBy = Tank1", Q.invitedBy, "Tank1")
  eq("stats.invited = 1", Q.stats.invited, 1)
  check("queue STAYS active on invite (so a decline can resume)", Q.active == true)
  check("alarm sound played", SOUND.played == true)
  -- a repeated Sync on the same invite must not re-alarm or double-count
  SOUND.played = false
  Q:Sync()
  eq("no duplicate invite count", Q.stats.invited, 1)
  check("no re-alarm while holding", SOUND.played == false)
  eq("ApplyNext refuses during a pending invite", Q:ApplyNext(), false)
end)

scenario("Queue: you DECLINE the invite -> resume + skip that leader", function()
  resetQueue(); allNeeded()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  Q:Start(); Q:ApplyNext(); RUNTIMERS()
  LFG.appInfo[1].applicationStatus = "invited"; Q:Sync()
  check("holding the invite", Q.invitedBy == "Tank1")
  LFG.appInfo[1].applicationStatus = "invitedeclined"; Q:Sync()
  eq("invitedBy cleared after you decline", Q.invitedBy, nil)
  check("queue resumes (still active)", Q.active == true)
  check("declined-invite leader skipped (blacklisted)", Q.blacklist["Tank1"] ~= nil)
  eq("application freed", Q.applied[1], nil)
end)

scenario("Queue: invite withdrawn/expired -> watchdog resumes", function()
  resetQueue(); allNeeded()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  Q:Start(); Q:ApplyNext(); RUNTIMERS()
  LFG.appInfo[1].applicationStatus = "invited"; Q:Sync()
  check("holding", Q.invitedBy == "Tank1")
  LFG.apps = {}; LFG.appInfo = {}   -- the client drops the application entirely
  GROUPN = 0
  Q:Sync()
  eq("invitedBy cleared by watchdog", Q.invitedBy, nil)
  check("still active (resumed)", Q.active == true)
end)

scenario("Queue: you ACCEPT the invite -> stop (the win)", function()
  resetQueue(); allNeeded()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  Q:Start(); Q:ApplyNext(); RUNTIMERS()
  LFG.appInfo[1].applicationStatus = "invited"; Q:Sync()
  LFG.appInfo[1].applicationStatus = "inviteaccepted"; Q:Sync()
  eq("invitedBy cleared on accept", Q.invitedBy, nil)
  check("queue stopped on accept", Q.active == false)
end)

scenario("Queue: join detected via roster (invite gone + grouped) -> stop", function()
  resetQueue(); allNeeded()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  Q:Start(); Q:ApplyNext(); RUNTIMERS()
  LFG.appInfo[1].applicationStatus = "invited"; Q:Sync()
  LFG.apps = {}; LFG.appInfo = {}; GROUPN = 5   -- invite gone AND you're now grouped
  Q:Sync(); GROUPN = 0
  eq("invitedBy cleared", Q.invitedBy, nil)
  check("stopped (joined)", Q.active == false)
end)

scenario("Queue Sync handles DECLINE (blacklist + free slot)", function()
  resetQueue(); allNeeded()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  Q:Start()
  Q:ApplyNext(); RUNTIMERS()
  LFG.appInfo[1].applicationStatus = "declined"
  Q:Sync()
  eq("stats.declined = 1", Q.stats.declined, 1)
  check("leader blacklisted", Q.blacklist["Tank1"] ~= nil)
  eq("application freed", Q.applied[1], nil)
  check("queue still active after a decline", Q.active == true)
end)

scenario("Queue won't apply in combat", function()
  resetQueue(); allNeeded()
  setResults({ { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", age = 30, num = 4, members = { 1, 0, 3 } } })
  INCOMBAT = true
  local fired = Q:ApplyNext(); RUNTIMERS()
  INCOMBAT = false
  check("combat blocks apply", fired == false)
  eq("nothing applied in combat", Q.stats.applied, 0)
end)

scenario("Queue stops when group fills", function()
  resetQueue()
  Q:Start()
  GROUPN = 5
  fire("GROUP_ROSTER_UPDATE")
  GROUPN = 0
  check("full group stops the queue", Q.active == false)
end)

-- -------------------------------- Core glue ------------------------------
scenario("Slash + keybind routing", function()
  resetQueue()
  ns.db.autoApply = false
  SlashCmdList["KEYQUEUE"]("auto")
  eq("/kq auto toggles ON", ns.db.autoApply, true)
  SlashCmdList["KEYQUEUE"]("auto")
  eq("/kq auto toggles OFF", ns.db.autoApply, false)

  SlashCmdList["KEYQUEUE"]("stop")
  check("/kq stop -> inactive", Q.active == false)

  check("KeyQueueApplyNext global exists", type(KeyQueueApplyNext) == "function")
  local ok = pcall(KeyQueueApplyNext)
  check("keybind handler runs without error", ok)
end)

-- -------------------------------- Core ticker ----------------------------
scenario("Core ticker body runs both branches", function()
  check("ticker captured", type(TICKERFN) == "function")
  resetQueue()
  ns.db.tab = "listings"
  local ok1 = pcall(TICKERFN)            -- idle branch (reads + refresh)
  check("ticker idle branch ok", ok1)
  Q:Start()
  local ok2 = pcall(TICKERFN)            -- active branch (Queue:Tick)
  check("ticker active branch ok", ok2)
  resetQueue()
end)

-- -------------------------------- UI smoke -------------------------------
scenario("UI render + debug dumps don't error", function()
  allNeeded()
  setResults({
    { rid = 1, aid = 2001, name = "+19 AA", leader = "Tank1", score = 3500, age = 30, num = 4, members = { 1, 0, 3 } },
    { rid = 2, aid = 2002, name = "+18 sky", leader = "L2", age = 10, members = { 1, 0, 2 } },
  })
  S:Read()
  for _, tab in ipairs({ "queue", "listings", "settings" }) do
    ns.db.tab = tab
    local ok, e = pcall(function() ns.UI:Refresh() end)
    check("UI:Refresh tab=" .. tab, ok, e)
  end
  check("UI:Debug ok",   (pcall(function() ns.UI:Debug() end)))
  check("UI:DumpApps ok",(pcall(function() ns.UI:DumpApps() end)))
  check("UI:DumpRaw ok", (pcall(function() ns.UI:DumpRaw() end)))
  ns.db.tab = "queue"
end)

-- ============================ report =====================================
local out = {}
out[#out + 1] = "==================== KeyQueue harness ===================="
for _, l in ipairs(LINES) do out[#out + 1] = l end
out[#out + 1] = "----------------------------------------------------------"
out[#out + 1] = string.format("RESULT: %d passed, %d failed (%d checks)", PASS, FAIL, PASS + FAIL)
if #PRINTLOG > 0 then
  out[#out + 1] = "------------------- addon print() output -----------------"
  for _, l in ipairs(PRINTLOG) do out[#out + 1] = "  | " .. l end
end
return table.concat(out, "\n"), FAIL
'''


def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    mods = {}
    for name in ORDER:
        with open(os.path.join(BASE, name), "rb") as fh:
            mods[name] = fh.read()
    g.MODS = lua.table_from(mods)
    report, nfail = lua.execute(HARNESS)
    print(report)
    return 1 if int(nfail) > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
