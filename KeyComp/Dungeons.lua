local _, ns = ...

-- =========================================================================
-- Per-dungeon removal/utility data (WoW Midnight S1, compiled from method.gg by
-- Tactyks). Originally a Disc dispel guide; now class-agnostic.
--
--   discCovers + required - together = every removal type this dungeon DEMANDS.
--       The split is historical: Coverage unions them into the demand set and
--       computes who covers each from the LIVE group's specs, so the tool works
--       for any class, not just Disc. (TODO: collapse into a single `demands` set.)
--   priority   - rough dispel intensity of the dungeon (class-agnostic)
--   note       - one-line summary
--   abilities  - the full checklist: { t = type, src = mob, ab = ability, kick = true? }
--                t in: magic/disease/curse/poison/bleed (ally debuffs), soothe (enrage), purge (enemy buff)
--                kick = the cast should be interrupted first
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
    MAGISTERS_TERRACE = {
        name = "Magister's Terrace",
        priority = "HIGHEST",
        discCovers = { magic = true, purge = true },
        required = {},
        note = "13 magic effects across trash + bosses \226\128\148 the heaviest magic load of the season.",
        abilities = {
            { t = "magic", src = "Arcane Sentry", ab = "Ethereal Shackles (root)" },
            { t = "magic", src = "Arcane Magister", ab = "Polymorph", kick = true },
            { t = "magic", src = "Lightward Healer", ab = "Holy Fire DoT" },
            { t = "magic", src = "Void Terror", ab = "Consuming Void" },
            { t = "magic", src = "Arcanotron Custos (B1)", ab = "Ethereal Shackles x2 (Mass Dispel)" },
            { t = "magic", src = "Degentrius (B4)", ab = "Hulking Fragment DoT (tank)" },
            { t = "magic", src = "Degentrius (B4)", ab = "Devouring Entropy" },
            { t = "purge", src = "Sunblade Enforcer", ab = "Arcane Blade (tank-buster buff)" },
            { t = "purge", src = "Lightward Healer", ab = "Power Word: Shield" },
            { t = "purge", src = "Seranel Sunlash (B2)", ab = "Hastening Ward (top value)" },
        },
    },
    MAISARA_CAVERNS = {
        name = "Maisara Caverns",
        priority = "VERY HIGH",
        discCovers = { magic = true, disease = true, purge = true },
        required = { soothe = true, poison = true, curse = true },
        note = "Hex is the most punishing dispel of the season. Final boss adds an enrage + a curse.",
        abilities = {
            { t = "magic", src = "Ritual Hexxer", ab = "Hex", kick = true },
            { t = "magic", src = "Tormented Shade", ab = "Spirit Rend DoT", kick = true },
            { t = "magic", src = "Hollow Soulrender", ab = "Frost Nova (root)" },
            { t = "magic", src = "Hex Guardian", ab = "Ritual Firebrand x2 (Mass Dispel)" },
            { t = "disease", src = "Muro'jin & Nekraxx (B1)", ab = "Infected Pinions" },
            { t = "purge", src = "Grim Skirmisher", ab = "Grim Ward (stagger purges)" },
            { t = "soothe", src = "Frenzied Berserker", ab = "Blood Frenzy (Enrage)" },
            { t = "poison", src = "Bramblemaw Bear", ab = "Poisons" },
        },
    },
    WINDRUNNER_SPIRE = {
        name = "Windrunner Spire",
        priority = "MODERATE",
        discCovers = { magic = true, purge = true },
        required = { curse = true, bleed = true, soothe = true, poison = true },
        note = "One key purge (Bolstering Flames). Also throws curse, bleeds, enrage and poison.",
        abilities = {
            { t = "magic", src = "Restless Steward", ab = "Soul Torment x2 (Mass Dispel)" },
            { t = "purge", src = "Territorial Dragonhawk", ab = "Bolstering Flames (purge on CD)" },
            { t = "curse", src = "Kalis (B2)", ab = "Curse of Darkness" },
            { t = "bleed", src = "Apex Lynx", ab = "Puncturing Bite" },
            { t = "bleed", src = "Spectral Axethrower", ab = "Throw Axe" },
            { t = "bleed", src = "Loyal Worg", ab = "Shred Flesh (heal absorb)" },
            { t = "soothe", src = "Phantasmal Mystic", ab = "Ephemeral Bloodlust (Enrage @50%)" },
            { t = "poison", src = "Creeping Spindleweb", ab = "Poison Spray" },
        },
    },
    NEXUS_POINT_XENAS = {
        name = "Nexus-Point Xenas",
        priority = "LOW-MODERATE",
        discCovers = { magic = true },
        required = { curse = true },
        note = "Light magic pressure. Main gap is the death-cast curse (Voidcaller).",
        abilities = {
            { t = "magic", src = "Corewright Arcanist", ab = "Transference (stops self-heal)" },
            { t = "curse", src = "Cursed Voidcaller", ab = "Creeping Void (on death)" },
        },
    },
    PIT_OF_SARON = {
        name = "Pit of Saron",
        priority = "MODERATE",
        discCovers = { magic = true, disease = true, purge = true },
        required = { curse = true, soothe = true },
        note = "Notable disease load. Curses (Krick) and an enrage to handle.",
        abilities = {
            { t = "magic", src = "Rimebone Coldwraith", ab = "Permeating Cold x2" },
            { t = "magic", src = "Dreadpulse Lich", ab = "Torrent of Misery" },
            { t = "magic", src = "Forgemaster Garfrost (B1)", ab = "Siphoning Chill (after Cryostomp)" },
            { t = "disease", src = "Rotting Ghoul", ab = "Rotting Strikes (tank)" },
            { t = "purge", src = "Deathwhisper Necrolyte", ab = "Necromantic Infusion" },
            { t = "curse", src = "Quarry Tormentor", ab = "Curse of Torment" },
            { t = "curse", src = "Shades of Krick (B2)", ab = "Shadowbind", kick = true },
            { t = "soothe", src = "Lumbering Plaguehorror", ab = "Plague Frenzy (Enrage)" },
        },
    },
    SEAT_OF_THE_TRIUMVIRATE = {
        name = "Seat of the Triumvirate",
        priority = "MODERATE",
        discCovers = { magic = true, purge = true },
        required = { soothe = true, bleed = true },
        note = "Bursty Mass Dispel windows. Enrage + bleed need other classes.",
        abilities = {
            { t = "magic", src = "Saprish", ab = "Howling Dark (fear, Mass Dispel)" },
            { t = "magic", src = "Famished Broken", ab = "Corrupting Touch" },
            { t = "magic", src = "L'ura (B4)", ab = "Rift Essence" },
            { t = "purge", src = "Dire Voidbender", ab = "Abyssal Enhancement" },
            { t = "soothe", src = "Shadowguard Champion", ab = "Battle Rage (Enrage)" },
            { t = "bleed", src = "Ruthless Riftstalker", ab = "Backstab (tank)" },
        },
    },
    SKYREACH = {
        name = "Skyreach",
        priority = "LOW",
        discCovers = { purge = true },
        required = { soothe = true, bleed = true },
        note = "Lowest magic pressure of the season \226\128\148 mostly purges. Enrage + bleeds need others.",
        abilities = {
            { t = "purge", src = "Outcast Warrior", ab = "Rushing Winds" },
            { t = "purge", src = "Blinding Sun Priestess", ab = "Solar Barrier (absorb)" },
            { t = "soothe", src = "Raging Squall", ab = "Wrathful Wind (Enrage)" },
            { t = "bleed", src = "Alpha Eagle / Bladetalon", ab = "Blade Rush / Peck" },
        },
    },
    ALGETHAR_ACADEMY = {
        name = "Algeth'ar Academy",
        priority = "LOW",
        discCovers = { magic = true },
        required = { soothe = true, bleed = true, poison = true },
        note = "Only 3 magic effects but Monotonous Lecture is critical. Enrage/bleed/poison need others.",
        abilities = {
            { t = "magic", src = "Unruly Textbook", ab = "Monotonous Lecture (sleep)", kick = true },
            { t = "magic", src = "Crawth trash", ab = "Energy Bomb" },
            { t = "magic", src = "Vexamus (B3)", ab = "Oversurge" },
            { t = "soothe", src = "Aggravated Skitterfly", ab = "Agitation (Enrage)" },
            { t = "soothe", src = "Alpha Eagle", ab = "Raging Screech (Enrage)" },
            { t = "bleed", src = "Vile Lasher / Territorial Eagle", ab = "Vile Bite / Peck" },
            { t = "poison", src = "Hungry Lashers (B1)", ab = "Lasher Toxin" },
        },
    },
}
