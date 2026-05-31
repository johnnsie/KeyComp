local _, ns = ...

-- =========================================================================
-- Roster: read the live group into { unit, name, class, spec, role, isPlayer }.
-- Player spec is read exactly (GetSpecialization); party members fall back to
-- assigned role, which is enough to resolve dispel capability for hybrids.
-- =========================================================================

local R = {}
ns.Roster = R

local function playerSpec()
    if not GetSpecialization then return nil, nil end
    local idx = GetSpecialization()
    if not idx then return nil, nil end
    local _, name, _, _, role = GetSpecializationInfo(idx)
    return name, role
end

local function entry(unit, isPlayer)
    local _, classFile = UnitClass(unit)
    return {
        unit = unit,
        name = (UnitName(unit)),
        class = classFile,
        role = UnitGroupRolesAssigned(unit),
        isPlayer = isPlayer or false,
    }
end

function R.Read()
    local roster = {}

    local me = entry("player", true)
    local specName, specRole = playerSpec()
    me.spec = specName
    if (not me.role or me.role == "NONE") and specRole then me.role = specRole end
    roster[#roster + 1] = me

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                roster[#roster + 1] = entry(unit)
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                roster[#roster + 1] = entry(unit)
            end
        end
    end

    return roster
end
