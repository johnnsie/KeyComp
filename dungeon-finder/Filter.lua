local _, ns = ...

-- =========================================================================
-- Filter: turn your saved settings into a resolved criteria set, decide which
-- listings qualify, and rank the survivors by how likely they are to invite you
-- fast. Tuned for a non-meta seeker who wants VOLUME: prefer near-full, fresh
-- listings (they pop soonest) where your role slot is actually open.
-- =========================================================================

local F = {}
ns.Filter = F

F.WEIGHTS = {
    fill   = 2.0,    -- per member already in the group (4/5 groups pop fastest)
    fresh  = 1.0,    -- newer listings are far more likely to still be active
    leader = 0.0005, -- mild nudge toward higher-rated leaders (likelier to time)
    exact  = 1.5,    -- bonus for matching your exact target key
}

local function specRole()
    if not GetSpecialization then return nil end
    local i = GetSpecialization()
    if not i then return nil end
    local _, _, _, _, role = GetSpecializationInfo(i)
    return role
end
F.specRole = specRole

-- your queue role: explicit override, else your current spec's role (HEALER for
-- Disc/Holy), else HEALER as a sensible last resort.
function F:Role()
    local db = ns.db
    return (db and db.role) or specRole() or "HEALER"
end

-- resolved criteria from saved settings (single source of truth for queue + UI).
function F:Criteria()
    local db = ns.db or {}
    local minKey = db.targetKey or 19
    local maxKey = math.max(minKey, db.keyMax or minKey)

    local dungeons
    if db.autoTargets ~= false then
        -- auto: only dungeons you haven't completed at the target key yet.
        dungeons = ns.Progress:NeededAt(minKey)
        -- if NOTHING is needed (you've already done them all, or progress hasn't
        -- loaded), fall back to ALL dungeons instead of matching nothing -- a farmer
        -- who's cleared every +19 still wants to see +19 groups.
        if not next(dungeons) then dungeons = nil end
    else
        -- manual: the dungeons you've ticked (nil db.dungeons = all on).
        dungeons = {}
        for _, key in ipairs(ns.Dungeons.order) do
            if not db.dungeons or db.dungeons[key] then dungeons[key] = true end
        end
    end

    return {
        role           = self:Role(),
        minKey         = minKey,
        maxKey         = maxKey,
        dungeons       = dungeons,                  -- set, or nil = all dungeons
        minLeaderScore = db.minLeaderScore or 0,
        skipGated      = db.skipGated ~= false,
        includeUnknownKey = db.includeUnknownKey or false,
    }
end

local function roleSlotOpen(r, role)
    if role == "TANK" then return r.tankOpen end
    if role == "HEALER" then return r.healOpen end
    return r.dpsOpen
end

-- ok, reason. ctx carries live state (your score, the blacklist) so Match stays pure.
function F:Match(r, c, ctx)
    -- dungeon set: only EXCLUDE a dungeon we can positively identify as not-needed
    -- (e.g. already done at the target). A listing whose dungeon name we couldn't
    -- map is NOT excluded -- we can't claim it's done, and it's still a Mythic+ key.
    if c.dungeons and r.dungeonKey and not c.dungeons[r.dungeonKey] then
        return false, "dungeon-done"
    end
    -- key level. Blizzard often doesn't expose the keystone (many leaders don't type "+N"
    -- in the title), so we only know it sometimes. A KNOWN key must be in range; a listing
    -- with NO readable key is KEPT and shown as "+?" -- hiding them all left the list empty
    -- when titles lack "+N". The apply paths are what stay strict: one-tap and the row
    -- buttons won't fire at a "+?" group unless you opt in (see Queue:Eligible). That keeps
    -- the list useful without ever signing you to an off-target key.
    if r.keyLevel and (r.keyLevel < c.minKey or r.keyLevel > c.maxKey) then
        return false, "key"
    end
    -- a slot for your role
    if not roleSlotOpen(r, c.role) then return false, "no-slot" end
    -- leader rating floor
    if c.minLeaderScore > 0 and (r.leaderScore or 0) < c.minLeaderScore then
        return false, "leader-score"
    end
    -- score gate: their required rating exceeds yours -> instant decline, skip it.
    -- Only when we actually know your score (> 0); an unreadable score must NOT
    -- silently filter out every gated listing.
    if c.skipGated and ctx and ctx.myScore and ctx.myScore > 0
        and r.requiredScore and r.requiredScore > 0 then
        if ctx.myScore < r.requiredScore then return false, "gated" end
    end
    -- recently declined this leader
    if ctx and ctx.blacklist and r.leaderName and ctx.blacklist[r.leaderName] then
        return false, "blacklist"
    end
    return true
end

function F:Score(r, c)
    local w = F.WEIGHTS
    local s = 0
    s = s + w.fill * (r.numMembers or 1)
    s = s + w.fresh * (math.max(0, 150 - (r.ageSeconds or 0)) / 30)
    s = s + w.leader * (r.leaderScore or 0)
    if r.keyLevel and r.keyLevel == c.minKey then s = s + w.exact end
    return s
end

-- filter + rank, AND tally why each non-match was dropped. Returns
-- (matched best-first, reasons map { reason = count }).
function F:Evaluate(results, c, ctx)
    local out, reasons = {}, {}
    for _, r in ipairs(results or {}) do
        local ok, why = self:Match(r, c, ctx)
        if ok then
            r.fitScore = self:Score(r, c)
            out[#out + 1] = r
        else
            reasons[why or "?"] = (reasons[why or "?"] or 0) + 1
        end
    end
    table.sort(out, function(a, b) return (a.fitScore or 0) > (b.fitScore or 0) end)
    return out, reasons
end

-- filter + rank. Returns the qualifying listings, best-to-apply first.
function F:Apply(results, c, ctx)
    local out = self:Evaluate(results, c, ctx)
    return out
end
