-- Demo.lua — populate the panel with a fake group + applicants for
-- screenshots / video, with no live group needed.
-- Toggle with:  /kc demo   and   /kc demo off
-- Hooks the data layer via KC._demoRoster / KC._demoApplicants, which
-- Roster.lua and Applicants.lua already short-circuit to when set.
local ADDON, KC = ...

-- A 5-man that covers most removals but leaves Bleed open (no class in the
-- capability matrix brings a Bleed dispel) -> a clean, honest "missing Bleed"
-- story for the Coverage strip.
local function demoRoster()
    return {
        { name = "Yourpriest", class = "PRIEST",  spec = "Discipline",    role = "HEALER",  isPlayer = true,  ilvl = 642, score = 3120 },
        { name = "Tankzilla",  class = "WARRIOR", spec = "Protection",    role = "TANK",    isPlayer = false, ilvl = 645, score = 2950 },
        { name = "Arcanee",    class = "MAGE",    spec = "Frost",         role = "DAMAGER", isPlayer = false, ilvl = 641, score = 3010 },
        { name = "Stabby",     class = "ROGUE",   spec = "Assassination", role = "DAMAGER", isPlayer = false, ilvl = 638, score = 2880 },
        { name = "Moonfang",   class = "DRUID",   spec = "Balance",       role = "DAMAGER", isPlayer = false, ilvl = 640, score = 2900 },
    }
end

local function m(name, class, spec, role, score, ilvl, key)
    return { name = name, class = class, spec = spec, role = role, score = score, ilvl = ilvl, bestKey = key }
end

-- A believable applicant pool. Each entry is one APPLICANT = a list of members;
-- entries with >1 member are premades that apply together (one Invite takes the
-- whole group) and render nested. Hunter/Mage are stacked so the "+N more"
-- expander is exercised too.
local function demoApplicants()
    return {
        -- tanks
        { m("Borkdk",     "DEATHKNIGHT", "Blood",        "TANK",    2890, 641, 13) },
        { m("Shieldwall", "WARRIOR",     "Protection",   "TANK",    2710, 639, 11) },
        -- a DPS + healer duo applying together (premade of 2)
        { m("Frostbyte",  "MAGE",        "Frost",        "DAMAGER", 3015, 641, 13),
          m("Bandaid",    "PRIEST",      "Holy",         "HEALER",  2980, 640, 12) },
        -- hunters stacked (3) -> "+2 more" expander on the Hunter row
        { m("Pewpewlol",  "HUNTER",      "Marksmanship", "DAMAGER", 3120, 642, 14) },
        { m("Legholas",   "HUNTER",      "Beast Mastery","DAMAGER", 2955, 640, 12) },
        { m("Quickshot",  "HUNTER",      "Survival",     "DAMAGER", 2680, 638, 10) },
        -- more dps (Pyroclast is a 2nd Mage -> Mage row gets "+1 more")
        { m("Pyroclast",  "MAGE",        "Fire",         "DAMAGER", 2840, 639, 11) },
        { m("Draganos",   "EVOKER",      "Devastation",  "DAMAGER", 3080, 642, 14) },
        { m("Backstabz",  "ROGUE",       "Assassination","DAMAGER", 2900, 640, 12) },
        -- a 3-stack premade applying together
        { m("Trinity",    "WARLOCK",     "Affliction",   "DAMAGER", 2870, 639, 11),
          m("Trinitwo",   "DEMONHUNTER", "Havoc",        "DAMAGER", 2810, 638, 10),
          m("Trinithree", "SHAMAN",      "Elemental",    "DAMAGER", 2790, 637, 10) },
        -- healer
        { m("Holymoly",   "PALADIN",     "Holy",         "HEALER",  2960, 641, 13) },
    }
end

function KC.StartDemo()
    KC._demoRoster = demoRoster()
    KC._demoApplicants = demoApplicants()
    KC._demo = true
    if KC.Show then KC.Show() end
    if KC.Refresh then KC.Refresh() end
    print("|cff66ccffKeyComp|r: demo mode ON - fake group + applicants. /kc demo off to clear.")
end

function KC.StopDemo()
    KC._demoRoster = nil
    KC._demoApplicants = nil
    KC._demo = false
    if KC.Refresh then KC.Refresh() end
    print("|cff66ccffKeyComp|r: demo mode OFF.")
end

-- Intercept "/kc demo" without touching Core's slash if-chain. Demo.lua loads
-- after Core.lua (see .toc), so `orig` is Core's handler; everything that
-- isn't a demo command is delegated straight through.
local orig = SlashCmdList["KEYCOMP"]
SlashCmdList["KEYCOMP"] = function(msg)
    local m = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if m == "demo" then
        KC.StartDemo()
    elseif m == "demo off" or m == "demooff" then
        KC.StopDemo()
    elseif orig then
        orig(msg)
    end
end
