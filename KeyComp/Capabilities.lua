local _, ns = ...

-- =========================================================================
-- Capabilities: who can remove / provide what. Verified against Warcraft Wiki
-- + Wowhead for The War Within / Midnight (12.0.x), May 2026.
--
-- Capability keys:
--   magic    - remove Magic from ALLIES   (HEALER specs only in modern WoW)
--   disease  - remove Disease from allies
--   poison   - remove Poison from allies
--   curse    - remove Curse from allies
--   purge    - remove Magic buff from ENEMIES (offensive)
--   soothe   - remove Enrage from enemies
--   bleed    - remove Bleed from allies   (Evoker Cauterizing Flame only)
--   interrupt- ANY hard interrupt (short OR long)
--   shortkick- a reliable short-cooldown interrupt (<= ~24s). Used for the
--              "need 2 kicks" rule. Long ones (Evoker Quell 40s, Shadow Silence
--              45s, Balance Solar Beam 60s, Resto Wind Shear 30s) set interrupt
--              but NOT shortkick.
--   lust     - Bloodlust / Heroism / Time Warp / Fury of the Aspects / Primal Rage
--   battlerez- combat resurrection (DK / Druid / Warlock)
--
-- Resolution returns confirmed + potential sets. Confirmed comes from known
-- spec, else assigned role (role is reliable for the healer-only magic case).
-- Key facts that surprise people:
--   * Death Knight has NO ally dispels at all.
--   * Magic dispel is healer-spec only.
--   * Curse: Mage (all specs), Druid (all, Remove Corruption), Evoker (Cauterizing),
--     Shaman (Resto = Purify Spirit, reliable -> confirmed; Ele/Enh = Cleanse Spirit
--     class talent -> "maybe"/potential, since you can't see their talents).
--   * Bleed: only Evoker (Cauterizing Flame).
--   * Soothe (Enrage): Druid, Hunter (Tranq), Rogue (Shiv), Evoker (Overawe talent).
-- =========================================================================

local Cap = {}
ns.Capabilities = Cap

local function set(...)
    local t = {}
    for i = 1, select("#", ...) do t[select(i, ...)] = true end
    return t
end

local function union(into, from)
    if from then for k in pairs(from) do into[k] = true end end
    return into
end

local CLASSES = {
    DEATHKNIGHT = {
        -- Mind Freeze (15s), Raise Ally. No dispels of any kind.
        always = set("interrupt", "shortkick", "battlerez"),
    },
    DEMONHUNTER = {
        -- Disrupt (15s), Consume Magic (purge).
        always = set("interrupt", "shortkick", "purge"),
    },
    DRUID = {
        -- Remove Corruption (curse+poison, all specs); Soothe; Rebirth.
        -- Magic only on Resto (Nature's Cure). Interrupt: Skull Bash (Feral/
        -- Guardian, short) or Solar Beam (Balance, 60s long). Resto: no interrupt.
        always = set("soothe", "battlerez", "curse", "poison"),
        byRole = {
            HEALER  = set("magic"),
            TANK    = set("interrupt", "shortkick"),
            DAMAGER = set("interrupt"),
        },
        bySpec = {
            Restoration = set("magic"),
            Guardian    = set("interrupt", "shortkick"),
            Feral       = set("interrupt", "shortkick"),
            Balance     = set("interrupt"),
        },
        potential = set("magic", "interrupt", "shortkick"),
    },
    EVOKER = {
        -- Cauterizing Flame (Bleed/Poison/Curse/Disease, 60s, all specs).
        -- Magic only on Preservation (Naturalize). Quell interrupt is ~40s (long,
        -- not a short kick). Overawe (talent) soothes Enrage. Fury of the Aspects.
        always = set("interrupt", "lust", "bleed", "poison", "curse", "disease"),
        byRole = { HEALER = set("magic") },
        bySpec = {
            Preservation = set("magic"),
            Devastation  = set(),
            Augmentation = set(),
        },
        potential = set("magic"),
        talented  = set("soothe"),
    },
    HUNTER = {
        -- Counter Shot / Muzzle (24s, short); Tranq Shot (soothe + purge);
        -- Primal Rage (lust, via pet).
        always = set("interrupt", "shortkick", "soothe", "purge", "lust"),
    },
    MAGE = {
        -- Counterspell (24s, short); Remove Curse (all specs); Spellsteal; Time Warp.
        always = set("interrupt", "shortkick", "curse", "purge", "lust"),
    },
    MONK = {
        -- Detox (Poison+Disease, all specs); Mistweaver adds Magic.
        -- Spear Hand Strike (15s).
        always = set("interrupt", "shortkick", "poison", "disease"),
        byRole = { HEALER = set("magic") },
        bySpec = { Mistweaver = set("magic") },
        potential = set("magic"),
    },
    PALADIN = {
        -- Cleanse Toxins (Poison+Disease, all specs); Holy Cleanse adds Magic.
        -- Rebuke (15s).
        always = set("interrupt", "shortkick", "poison", "disease"),
        byRole = { HEALER = set("magic") },
        bySpec = { Holy = set("magic") },
        potential = set("magic"),
    },
    PRIEST = {
        -- Dispel Magic / Mass Dispel (purge, all specs). Purify Disease (all specs).
        -- Magic dispel on Disc/Holy (Purify). Shadow's only interrupt is Silence
        -- (45s, long) -> interrupt but NOT shortkick.
        always = set("purge", "disease"),
        byRole = {
            HEALER  = set("magic"),
            DAMAGER = set("interrupt"),
        },
        bySpec = {
            Discipline = set("magic"),
            Holy       = set("magic"),
            Shadow     = set("interrupt"),
        },
        potential = set("magic", "interrupt"),
    },
    ROGUE = {
        -- Kick (15s); Shiv (soothe).
        always = set("interrupt", "shortkick", "soothe"),
    },
    SHAMAN = {
        -- Wind Shear (interrupt, all specs; 12s Ele/Enh = short, 30s Resto = long).
        -- Purge; Bloodlust. Magic dispel only on Resto (Purify Spirit).
        -- Curse: Resto removes it reliably (Purify Spirit) -> confirmed. Ele/Enh CAN
        -- remove curse too, via the Cleanse Spirit class talent -- but it's an optional
        -- pick you can't see in the group finder, so it's "maybe" (potential), not
        -- confirmed. Cleanse Spirit is available to every spec, so curse lives in
        -- `talented` (which Resolve always merges into potential).
        always = set("interrupt", "purge", "lust"),
        byRole = {
            HEALER  = set("magic", "curse"),
            DAMAGER = set("shortkick"),
        },
        bySpec = {
            Restoration = set("magic", "curse"),
            Elemental   = set("shortkick"),
            Enhancement = set("shortkick"),
        },
        talented  = set("curse"),
        potential = set("magic", "curse", "shortkick"),
    },
    WARLOCK = {
        -- Soulstone (battlerez). Pet (Felhunter): Devour Magic (magic + purge),
        -- Spell Lock (interrupt, 24s short) -- all pet-gated, so "maybe".
        always = set("battlerez"),
        talented = set("magic", "purge", "interrupt", "shortkick"),
        potential = set("magic", "purge", "interrupt", "shortkick"),
    },
    WARRIOR = {
        -- Pummel (15s).
        always = set("interrupt", "shortkick"),
    },
}

Cap.classes = CLASSES

-- Raid buffs by provider class (class-wide, spec-independent).
Cap.BUFFS = {
    { name = "Intellect",    class = "MAGE" },
    { name = "Stamina",      class = "PRIEST" },
    { name = "Attack Power", class = "WARRIOR" },
    { name = "Versatility",  class = "DRUID" },
    { name = "Chaos Brand",  class = "DEMONHUNTER" },
    { name = "Mystic Touch", class = "MONK" },
    { name = "Skyfury",      class = "SHAMAN" },
}

-- Returns confirmed, potential (two sets of capability keys).
function Cap.Resolve(classFile, specName, role)
    local c = CLASSES[classFile]
    local confirmed, potential = {}, {}
    if not c then return confirmed, potential end

    union(confirmed, c.always)

    local specHit = specName and c.bySpec and c.bySpec[specName]
    local roleHit = role and c.byRole and c.byRole[role]
    if specHit then
        union(confirmed, specHit)
    elseif roleHit then
        union(confirmed, roleHit)
    end

    union(potential, confirmed)
    if not specHit and not roleHit then
        union(potential, c.potential)
    end
    union(potential, c.talented)

    return confirmed, potential
end

-- Best-case union of everything a class could ever provide (for suggestions).
function Cap.ClassCanProvide(classFile)
    local c = CLASSES[classFile]
    local s = {}
    if not c then return s end
    union(s, c.always)
    union(s, c.potential)
    union(s, c.talented)
    if c.byRole then for _, v in pairs(c.byRole) do union(s, v) end end
    if c.bySpec then for _, v in pairs(c.bySpec) do union(s, v) end end
    return s
end

function Cap.ProvidersFor(removalType)
    local list = {}
    for classFile in pairs(CLASSES) do
        if Cap.ClassCanProvide(classFile)[removalType] then
            list[#list + 1] = classFile
        end
    end
    table.sort(list)
    return list
end
