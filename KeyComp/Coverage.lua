local _, ns = ...

-- =========================================================================
-- Coverage: given a roster and a dungeon, compute removal coverage and
-- group-utility coverage. Status per removal type:
--   covered (green) - at least one member confirmed to have it
--   maybe   (yellow)- none confirmed, but someone potentially has it
--   missing (red)   - nobody can do it
-- =========================================================================

local C = {}
ns.Coverage = C

C.REMOVAL_ORDER = { "magic", "disease", "curse", "poison", "bleed", "soothe", "purge" }

C.LABELS = {
    magic = "Magic", disease = "Disease", curse = "Curse", poison = "Poison",
    bleed = "Bleed", soothe = "Soothe", purge = "Purge",
    interrupt = "Interrupt", shortkick = "Kick", lust = "Bloodlust", battlerez = "Battle Rez",
}

function C.Compute(roster, dungeonKey)
    local dungeon = ns.Dungeons.list[dungeonKey]

    local relevant = {}
    if dungeon then
        for k, v in pairs(dungeon.discCovers) do if v then relevant[k] = true end end
        for k in pairs(dungeon.required) do relevant[k] = true end
    else
        for _, k in ipairs(C.REMOVAL_ORDER) do relevant[k] = true end
    end

    -- resolve each member's capabilities once
    local resolved = {}
    for _, m in ipairs(roster) do
        local conf, pot = ns.Capabilities.Resolve(m.class, m.spec, m.role)
        resolved[#resolved + 1] = { m = m, conf = conf, pot = pot }
    end

    local function providers(capKey)
        local conf, maybe = {}, {}
        for _, r in ipairs(resolved) do
            if r.conf[capKey] then
                conf[#conf + 1] = r.m
            elseif r.pot[capKey] then
                maybe[#maybe + 1] = r.m
            end
        end
        return conf, maybe
    end

    local removal = {}
    for _, t in ipairs(C.REMOVAL_ORDER) do
        if relevant[t] then
            local by, maybeBy = providers(t)
            local status = (#by > 0 and "covered") or (#maybeBy > 0 and "maybe") or "missing"
            removal[t] = {
                status = status,
                by = by,
                maybeBy = maybeBy,
                required = true,  -- every shown type is a mechanic this dungeon demands
            }
        end
    end

    local kConf, kMaybe = providers("shortkick")
    local lConf, lMaybe = providers("lust")
    local rConf, rMaybe = providers("battlerez")
    local longKick = {}
    for _, r in ipairs(resolved) do
        if r.conf.interrupt and not r.conf.shortkick then longKick[#longKick + 1] = r.m end
    end
    local utility = {
        kick      = { conf = kConf, maybe = kMaybe, want = 2 },
        longkick  = longKick,
        lust      = { conf = lConf, maybe = lMaybe, want = 1 },
        battlerez = { conf = rConf, maybe = rMaybe, want = 1 },
    }

    -- a gap = any removal type this dungeon demands that nobody in the group covers
    -- (was gated on a Disc-only "required" subset; now class-agnostic, computed from
    -- the live roster including you).
    local missing = {}
    for t, info in pairs(removal) do
        if info.status ~= "covered" then missing[t] = true end
    end

    local presentClass = {}
    for _, r in ipairs(resolved) do presentClass[r.m.class] = true end
    local buffs = {}
    for _, b in ipairs(ns.Capabilities.BUFFS or {}) do
        buffs[#buffs + 1] = { name = b.name, class = b.class, have = presentClass[b.class] or false }
    end

    -- the player's own resolved entry + which demanded removal types YOUR spec
    -- covers (drives the Info tab's "you" highlights, class-agnostic).
    local player, youCovers = nil, {}
    for _, r in ipairs(resolved) do
        if r.m.isPlayer then player = r; break end
    end
    if player then
        for t in pairs(relevant) do if player.conf[t] then youCovers[t] = true end end
    end

    return { removal = removal, utility = utility, missing = missing, buffs = buffs,
             relevant = relevant, resolved = resolved, youCovers = youCovers, player = player }
end
