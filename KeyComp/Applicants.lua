local _, ns = ...

-- =========================================================================
-- Applicants: read people applying to YOUR Premade listing, score each against
-- the group's current gaps, and rank them with a tunable priority formula.
--
-- NOTE: depends on the C_LFGList API. Written defensively, but UNVERIFIED
-- in-client -- expect to confirm field positions live.
-- =========================================================================

local A = {}
ns.Applicants = A

-- statuses we still show: pending + invited-but-not-yet-joined.
-- declined/timed-out/cancelled drop off, and once they JOIN they leave the
-- applicant list entirely (so they disappear on their own).
local VISIBLE_STATUS = { applied = true, invited = true, inviteaccepted = true }
-- an invite has been SENT (WoW often keeps status="applied" and flags this in pendingStatus)
local INVITED_STATUS = { invited = true, inviteaccepted = true }

-- ------------------------------------------------------------- priority ----
-- Tunable formula for ranking applicants within a class. Inputs:
--   score   - in-game M+ rating (the "RIO" number) from the application
--   ilvl    - equipped item level
--   bestKey - best key level the applicant has LOGGED for the selected dungeon
-- bestKey now comes from the baked WCL M+ data (ns.WCL); it's 0 for applicants
-- not in the dataset (top-ladder only), so they rank on M+ score + ilvl as
-- before. Tweak WEIGHTS to taste.
A.WEIGHTS = { score = 1.0, ilvl = 1.0, bestKey = 2.5 }
A.ILVL_BASE = 600

-- Best logged key for this applicant: WCL key for the SELECTED dungeon, else
-- their best logged key anywhere, else 0 (not in the dataset).
function A.GetBestKey(member, dungeonKey)
    if not (ns.WCL and ns.WCL.IsLoaded and ns.WCL:IsLoaded()) then return 0 end
    if not (member and member.name) then return 0 end
    local rec = ns.WCL:Lookup(member.name)
    if not rec then return 0 end
    local stat = ns.WCL:DungeonStat(rec, dungeonKey)
    if stat and stat.k then return stat.k end
    return rec.bk or 0
end

function A.PriorityScore(member, dungeonKey)
    if not member then return 0 end
    local w = A.WEIGHTS
    local score = member.score or 0
    local ilvl = member.ilvl or 0
    local bestKey = A.GetBestKey(member, dungeonKey) or 0
    return w.score * (score / 100)
        + w.ilvl * (math.max(0, ilvl - A.ILVL_BASE) / 5)
        + w.bestKey * bestKey
end

-- --------------------------------------------------------------- reading ---
function A.HasListing()
    return (C_LFGList and C_LFGList.HasActiveEntry and C_LFGList.HasActiveEntry()) and true or false
end

local function roleFrom(assignedRole, tank, healer, damage)
    if assignedRole and assignedRole ~= "NONE" then return assignedRole end
    if healer then return "HEALER" end
    if tank then return "TANK" end
    if damage then return "DAMAGER" end
    return nil
end

-- returns list of { applicantID, members, fills, isGroup, status, priority }
function A.Read(needs, dungeonKey)
    local out = {}
    if not (C_LFGList and C_LFGList.GetApplicants and C_LFGList.GetApplicantMemberInfo) then
        return out
    end
    local ids = C_LFGList.GetApplicants()
    if not ids then return out end
    needs = needs or {}

    -- pass 1: read applicants + their combined capability set
    for _, appID in ipairs(ids) do
        local status, pending
        if C_LFGList.GetApplicantInfo then
            -- returns LfgApplicantData: (applicantID, applicationStatus, pendingApplicationStatus, ...)
            -- as a table on modern builds, or positionally on older ones
            local a, b, c = C_LFGList.GetApplicantInfo(appID)
            if type(a) == "table" then
                status = a.applicationStatus or a.status or a.applicantStatus
                pending = a.pendingApplicationStatus or a.pendingStatus
            else
                status, pending = b, c
            end
        end
        -- keep only active applicants; cancelled/timedout/declined/failed are dropped
        if status == nil or VISIBLE_STATUS[status] then
            local members, caps = {}, {}
            for i = 1, 5 do
                local name, classFile, locClass, level, itemLevel, honorLevel,
                      tank, healer, damage, assignedRole, relationship, dungeonScore =
                      C_LFGList.GetApplicantMemberInfo(appID, i)
                if not name then break end
                local role = roleFrom(assignedRole, tank, healer, damage)
                members[#members + 1] = {
                    name = name, class = classFile, role = role,
                    ilvl = itemLevel, score = dungeonScore,
                }
                -- role-based capability (applicant spec isn't reliably exposed;
                -- role disambiguates the spec-sensitive case, i.e. healer Magic)
                local conf, pot = ns.Capabilities.Resolve(classFile, nil, role)
                for k in pairs(conf) do caps[k] = true end
                for k in pairs(pot) do caps[k] = true end
            end
            if #members > 0 then
                out[#out + 1] = {
                    applicantID = appID,
                    members = members,
                    isGroup = #members > 1,
                    status = status,
                    invited = (INVITED_STATUS[status] or INVITED_STATUS[pending]) and true or false,
                    caps = caps,
                    priority = A.PriorityScore(members[1], dungeonKey),
                }
            end
        end
    end

    -- pass 2: fills = which of the group's current needs this applicant covers.
    -- Computed against the ORIGINAL needs for everyone (NOT reduced by who you've
    -- invited), so inviting one applicant never blanks out what another applicant
    -- is shown to bring. Needs only shift when someone actually JOINS the party
    -- and coverage recomputes.
    for _, app in ipairs(out) do
        local fills = {}
        for k in pairs(needs) do
            if app.caps[k] then fills[#fills + 1] = k end
        end
        app.fills = fills
    end

    table.sort(out, function(a, b)
        if #a.fills ~= #b.fills then return #a.fills > #b.fills end
        return (a.priority or 0) > (b.priority or 0)
    end)

    return out
end
