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
        { name = "Yourpriest", class = "PRIEST",  role = "HEALER",  isPlayer = true  },
        { name = "Tankzilla",  class = "WARRIOR", role = "TANK",    isPlayer = false },
        { name = "Arcanee",    class = "MAGE",    role = "DAMAGER", isPlayer = false },
        { name = "Stabby",     class = "ROGUE",   role = "DAMAGER", isPlayer = false },
        { name = "Moonfang",   class = "DRUID",   role = "DAMAGER", isPlayer = false },
    }
end

local function app(name, class, role, score, ilvl, key)
    return { name = name, class = class, role = role, appID = -1,
             score = score, ilvl = ilvl, bestKey = key }
end

-- A believable applicant pool: several classes, varied M+ score / ilvl / key so
-- the ranking + top-N-per-class collapse are visible.
local function demoApplicants()
    return {
        -- tanks
        app("Borkdk",     "DEATHKNIGHT", "TANK",    2890, 641, 13),
        app("Shieldwall", "WARRIOR",     "TANK",    2710, 639, 11),
        -- dps
        app("Pewpewlol",  "HUNTER",      "DAMAGER", 3120, 642, 14),
        app("Legholas",   "HUNTER",      "DAMAGER", 2955, 640, 12),
        app("Quickshot",  "HUNTER",      "DAMAGER", 2680, 638, 10),
        app("Frostbyte",  "MAGE",        "DAMAGER", 3015, 641, 13),
        app("Pyroclast",  "MAGE",        "DAMAGER", 2840, 639, 11),
        app("Draganos",   "EVOKER",      "DAMAGER", 3080, 642, 14),
        app("Backstabz",  "ROGUE",       "DAMAGER", 2900, 640, 12),
        -- healer
        app("Holymoly",   "PALADIN",     "HEALER",  2960, 641, 13),
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
