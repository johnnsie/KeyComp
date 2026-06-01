local addonName, ns = ...

-- =========================================================================
-- UI: tabbed, movable, scrollable panel for forming Mythic+ groups (any class).
--   Coverage  - status strip (hover) + group + utility + gaps + missing buffs
--   Applicants- live LFG applicants grouped by role then collapsed to the
--               top-rated player PER CLASS (a class-comparison view)
--   Info      - dungeon priority, coverage split, key dispels
-- Header + tabs are fixed; everything below scrolls.
-- =========================================================================

local UI = {}
ns.UI = UI
UI.invitedLocal = {}  -- applicantIDs we've clicked Invite on this session (optimistic)
UI.expandedClasses = {}  -- {["DAMAGER:MAGE"]=true} class groups expanded to show every applicant

local C = ns.Coverage

local PAD = 14
local WIDTH = 470
local CONTENT_TOP = 118
local MAX_VIS = 380
local LX = 6
local APPL_MAX_ROWS = 40  -- pooled rows on the Applicants tab (leaders + nested members)

local GREEN  = "|cff40ff40"
local YELLOW = "|cffffd200"
local RED    = "|cffff5555"
local GREY   = "|cff999999"
local WHITE  = "|cffffffff"
local WCLC   = "|cffb389ff"  -- WCL purple (M+ DPS data)
local MEDAL_CODE = { g = "|cffffd100", s = "|cffc7c7cf", b = "|cffcd7f32" }  -- WCL gold/silver/bronze
-- status marks as textures (the ✓/✗ glyphs are tofu in WoW's default font)
local OK_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t"
local NO_ICON = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14:0:0|t"
local R      = "|r"

local STATUS = {
    covered = { 0.20, 0.70, 0.25 },
    maybe   = { 0.85, 0.70, 0.10 },
    missing = { 0.75, 0.18, 0.18 },
}

local PRIORITY_COLOR = {
    HIGHEST          = "|cffff2020",
    ["VERY HIGH"]    = "|cffff6a20",
    MODERATE         = "|cffffd200",
    ["LOW-MODERATE"] = "|cffd2e860",
    LOW              = "|cff60d060",
}

local ROLE_DISPLAY = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

local REMOVAL_ICON = {
    magic   = "Interface\\Icons\\Spell_Holy_DispelMagic",
    disease = "Interface\\Icons\\Spell_Holy_NullifyDisease",
    poison  = "Interface\\Icons\\Spell_Nature_NullifyPoison",
    curse   = "Interface\\Icons\\Spell_Holy_RemoveCurse",
    bleed   = "Interface\\Icons\\Ability_Rogue_Rupture",
    soothe  = "Interface\\Icons\\Spell_Nature_Drowsy",
    purge   = "Interface\\Icons\\Spell_Nature_Purge",
}
local REMOVAL_SHORT = {
    magic = "Magic", disease = "Disease", curse = "Curse", poison = "Poison",
    bleed = "Bleed", soothe = "Soothe", purge = "Purge",
}

-- icons for the compact applicant rows (removal types + utility)
local FILL_ICON = {
    magic   = "Interface\\Icons\\Spell_Holy_DispelMagic",
    disease = "Interface\\Icons\\Spell_Holy_NullifyDisease",
    poison  = "Interface\\Icons\\Spell_Nature_NullifyPoison",
    curse   = "Interface\\Icons\\Spell_Holy_RemoveCurse",
    bleed   = "Interface\\Icons\\Ability_Rogue_Rupture",
    soothe  = "Interface\\Icons\\Spell_Nature_Drowsy",
    purge   = "Interface\\Icons\\Spell_Nature_Purge",
    interrupt = "Interface\\Icons\\Spell_Frost_IceShock",
    shortkick = "Interface\\Icons\\Ability_Kick",
    lust      = "Interface\\Icons\\Spell_Nature_BloodLust",
    battlerez = "Interface\\Icons\\Spell_Nature_Reincarnation",
}

local CAP_ORDER = { "magic", "disease", "curse", "poison", "bleed", "soothe", "purge", "shortkick", "interrupt", "lust", "battlerez" }

-- ------------------------------------------------------------- helpers ----
local function classColorStr(classFile)
    local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    return col and col.colorStr
end

local function classColorRGB(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function ccName(m)
    local nm = m.name or "?"
    if m.isPlayer then nm = nm .. " " .. GREY .. "(you)" .. R end
    local cs = classColorStr(m.class)
    if cs then return "|c" .. cs .. nm .. R end
    return nm
end

local function classColored(classFile)
    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
    local cs = classColorStr(classFile)
    if cs then return "|c" .. cs .. name .. R end
    return name
end

local function plainNames(list)
    local t = {}
    for _, m in ipairs(list) do t[#t + 1] = (m.name or "?") .. (m.isPlayer and " (you)" or "") end
    return table.concat(t, ", ")
end

local function rgbHex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function classIconInline(classFile, size)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if not c then return "" end
    local s = size or 18
    return string.format("|TInterface\\TargetingFrame\\UI-Classes-Circles:%d:%d:0:0:256:256:%d:%d:%d:%d|t ",
        s, s, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

-- inline tank/healer/dps role icon. Uses the modern role atlases — the old
-- UI-LFG-ICON-PORTRAITROLES texture path renders blank on Midnight (12.x).
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local function roleIconInline(role, size)
    local a = ROLE_ATLAS[role]
    if not a then return "" end
    local s = size or 13
    if CreateAtlasMarkup then return CreateAtlasMarkup(a, s, s) .. " " end
    return "|A:" .. a .. ":" .. s .. ":" .. s .. "|a "
end

-- applicant table column geometry: x offset within a row + width. The row button
-- is anchored at LX+4, so a column's child-space x is LX + 4 + APPLCOLS[c].x.
local APPLCOLS = {
    name  = { x = 0,   w = 132 },  -- class icon + name (+ group/+N badge)
    score = { x = 136, w = 36 },   -- M+ score (rio) — 36px fits a 4-digit rating
    ilvl  = { x = 176, w = 30 },   -- equipped item level (next to M+)
    wcl   = { x = 210, w = 62 },   -- WCL M+: "+key dps" for the selected dungeon
    icons = { x = 276, w = 74 },   -- ability (fill) icons — last (right edge held at 350)
}

local function fillIconsInline(fills)
    local t = {}
    for _, fkey in ipairs(fills) do
        local ic = FILL_ICON[fkey]
        if ic then t[#t + 1] = "|T" .. ic .. ":14:14:0:0|t" end
    end
    return table.concat(t, " ")
end

-- "|cAARRGGBB" color escape for an M+ rating, using the game's own rarity ramp.
-- M+ rating tiers above the game's own ramp: gold >= 3700, platinum >= 4000.
local RIO_GOLD, RIO_PLAT = 3700, 4000
local function scoreColorCode(score)
    if score then
        if score >= RIO_PLAT then return "|cff66ddff" end   -- platinum
        if score >= RIO_GOLD then return "|cffffcc00" end    -- gold
    end
    if score and score > 0 and C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        local c = C_ChallengeMode.GetDungeonScoreRarityColor(score)
        if c and c.GenerateHexColor then return "|c" .. c:GenerateHexColor() end
    end
    return GREY
end

-- item level tiered color: high = uncommon green, solid = white, low = grey.
-- thresholds tuned for Midnight S1 gear (~600-660).
local function ilvlColorCode(ilvl)
    if not ilvl or ilvl <= 0 then return GREY end
    if ilvl >= 645 then return "|cff1eff00"
    elseif ilvl >= 635 then return WHITE
    else return GREY end
end

-- rarity color as r,g,b components (for tooltip AddLine, which wants components).
local function scoreRGB(score)
    if score then
        if score >= RIO_PLAT then return 0.40, 0.87, 1.0 end   -- platinum
        if score >= RIO_GOLD then return 1.0, 0.80, 0.0 end     -- gold
    end
    if score and score > 0 and C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        local c = C_ChallengeMode.GetDungeonScoreRarityColor(score)
        if c then return c.r, c.g, c.b end
    end
    return 0.85, 0.85, 0.85
end

local function hideTip() GameTooltip:Hide() end

-- ---------------------------------------------------------------- build ----
function UI:Init()
    if self.frame then return end
    if ns.db and not ns.db.tab then ns.db.tab = "coverage" end
    if ns.db and ns.db.scale == nil then ns.db.scale = 1 end

    local f = CreateFrame("Frame", "KeyCompFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(WIDTH, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
    f:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetScale((ns.db and ns.db.scale) or 1)

    local function stopMoving()
        if not f.isMoving then return end
        f:SetScript("OnUpdate", nil)
        f:StopMovingOrSizing()
        f.isMoving = false
        UI:SavePosition()
    end
    f:SetScript("OnMouseDown", function(self2, button)
        if button ~= "LeftButton" or self2.isMoving then return end
        self2:StartMoving()
        self2.isMoving = true
        self2:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then stopMoving() end
        end)
    end)
    f:SetScript("OnMouseUp", function() stopMoving() end)
    f:SetScript("OnHide", function() stopMoving() end)
    f:Hide()

    UI:RestorePosition()

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() UI:Hide() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText(WHITE .. "KeyComp" .. R)

    self.updatedText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.updatedText:SetPoint("TOPRIGHT", -30, -PAD - 2)

    local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prev:SetSize(26, 22); prev:SetText("<")
    prev:SetPoint("TOPLEFT", PAD, -40)
    prev:SetScript("OnClick", function() UI:CycleDungeon(-1) end)

    local nextb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextb:SetSize(26, 22); nextb:SetText(">")
    nextb:SetPoint("TOPRIGHT", -PAD, -40)
    nextb:SetScript("OnClick", function() UI:CycleDungeon(1) end)

    local dname = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dname:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    dname:SetPoint("RIGHT", nextb, "LEFT", -4, 0)
    dname:SetJustifyH("CENTER")
    self.dname = dname

    local auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    auto:SetSize(20, 20)
    auto:SetPoint("TOPLEFT", PAD - 2, -64)
    auto:SetScript("OnClick", function(self2)
        ns.db.auto = self2:GetChecked() and true or false
        UI:Refresh()
    end)
    auto:SetScript("OnEnter", function(self2)
        GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-detect dungeon", 1, 1, 1)
        GameTooltip:AddLine("Follows the dungeon you're inside, or the one your Premade listing is for.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    auto:SetScript("OnLeave", hideTip)
    self.autoCheck = auto

    local autoLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoLabel:SetPoint("LEFT", auto, "RIGHT", 2, 0)
    self.autoLabel = autoLabel

    -- tab bar
    local function makeTab(key, label, x)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(96, 24)
        b:SetPoint("TOPLEFT", x, -90)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetAllPoints(b)
        b.text:SetText(label)
        b.underline = b:CreateTexture(nil, "OVERLAY")
        b.underline:SetColorTexture(0.95, 0.82, 0.20, 1)
        b.underline:SetHeight(2)
        b.underline:SetPoint("BOTTOMLEFT", 6, -1)
        b.underline:SetPoint("BOTTOMRIGHT", -6, -1)
        b:SetScript("OnClick", function()
            ns.db.tab = key
            if UI.scroll then UI.scroll:SetVerticalScroll(0) end
            UI:Refresh()
        end)
        b.key = key
        return b
    end
    self.tabs = {
        makeTab("coverage", "Coverage", PAD),
        makeTab("applicants", "Applicants", PAD + 100),
    }
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(0.3, 0.3, 0.35, 0.8)
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", PAD, -113)
    div:SetPoint("TOPRIGHT", -PAD, -113)

    -- scroll area (content below the divider scrolls)
    local childW = WIDTH - 2 * (PAD - 2)
    self.childW = childW
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", PAD - 2, -CONTENT_TOP)
    scroll:SetSize(childW, 100)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        local range = math.max(0, (s.contentHeight or 0) - s:GetHeight())
        local nw = s:GetVerticalScroll() - delta * 34
        if nw < 0 then nw = 0 elseif nw > range then nw = range end
        s:SetVerticalScroll(nw)
        UI:UpdateScrollHint()
    end)
    self.scroll = scroll
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(childW, 100)
    scroll:SetScrollChild(child)
    self.child = child

    self.scrollHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.scrollHint:SetPoint("BOTTOMRIGHT", -PAD, PAD - 4)
    self.scrollHint:SetText(GREY .. "scroll \226\150\188" .. R)
    self.scrollHint:Hide()

    -- ---- per-tab widget pools (parented to the scroll child) ----
    local FSW = childW - 2 * LX
    local function fs(tmpl)
        local s = child:CreateFontString(nil, "OVERLAY", tmpl or "GameFontHighlightSmall")
        s:SetJustifyH("LEFT")
        s:SetWidth(FSW)
        s:SetWordWrap(true)
        return s
    end
    local function rowButton(w, h)
        local b = CreateFrame("Button", nil, child)
        b:SetSize(w, h or 15)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT")
        b.text:SetJustifyH("LEFT")
        b:SetScript("OnLeave", hideTip)
        return b
    end

    -- coverage tab
    self.cells = {}
    for i = 1, 7 do
        local cell = CreateFrame("Button", nil, child)
        cell:SetSize(38, 38)
        cell.bg = cell:CreateTexture(nil, "BACKGROUND")
        cell.bg:SetAllPoints()
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("TOPLEFT", 2, -2)
        cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        cell.label = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
        cell:SetScript("OnLeave", hideTip)
        self.cells[i] = cell
    end
    -- utility cells (kick / lust / battle rez): same look as the ability cells,
    -- pinned to the right end of the strip.
    self.utilCells = {}
    for i = 1, 3 do
        local cell = CreateFrame("Button", nil, child)
        cell:SetSize(38, 38)
        cell.bg = cell:CreateTexture(nil, "BACKGROUND")
        cell.bg:SetAllPoints()
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("TOPLEFT", 2, -2)
        cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        cell.label = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
        cell:SetScript("OnLeave", hideTip)
        self.utilCells[i] = cell
    end
    -- role-composition recap icons (ideal 1 tank / 1 heal / 3 dps; lit = filled)
    self.roleSlots = {}
    for i = 1, 5 do
        local t = child:CreateTexture(nil, "ARTWORK")
        t:SetSize(20, 20)
        t:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        t:Hide()
        self.roleSlots[i] = t
    end
    self.h_group = fs("GameFontNormal")
    self.memberBtns = {}
    for i = 1, 5 do
        local b = rowButton(FSW, 15)
        b.score = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.score:SetPoint("RIGHT", b, "RIGHT", 0, 0); b.score:SetWidth(52); b.score:SetJustifyH("RIGHT")
        b.ilvl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.ilvl:SetPoint("RIGHT", b, "RIGHT", -60, 0); b.ilvl:SetWidth(40); b.ilvl:SetJustifyH("RIGHT")
        b.text:SetWidth(FSW - 112); b.text:SetWordWrap(false)
        self.memberBtns[i] = b
    end
    self.utilText = fs()
    self.gapsText = fs()
    self.buffsText = fs()

    -- applicants tab
    self.h_appl = fs("GameFontNormal")
    self.applEmpty = fs()
    self.applSecHeaders = {}
    for i = 1, 3 do
        local h = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetJustifyH("LEFT")
        self.applSecHeaders[i] = h
    end
    self.applBoxes = {}
    for i = 1, 3 do
        local box = CreateFrame("Frame", nil, child, "BackdropTemplate")
        box:EnableMouse(false)
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        box:SetBackdropColor(1, 1, 1, 0.04)
        box:Hide()
        self.applBoxes[i] = box
    end
    self.applBtns = {}
    for i = 1, APPL_MAX_ROWS do
        local row = CreateFrame("Button", nil, child)
        row:SetSize(childW - 16, 18)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(0.20, 0.70, 0.25, 0.18)
        row.hl:Hide()
        row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.07)
        row.hover:Hide()
        local function col(x, w, justify)
            local s = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            s:SetPoint("LEFT", x, 0)
            s:SetWidth(w)
            s:SetJustifyH(justify or "LEFT")
            s:SetWordWrap(false)
            return s
        end
        -- numeric columns right-align so digits line up as clean columns
        row.name  = col(APPLCOLS.name.x,  APPLCOLS.name.w)
        row.score = col(APPLCOLS.score.x, APPLCOLS.score.w, "RIGHT")
        row.ilvl  = col(APPLCOLS.ilvl.x,  APPLCOLS.ilvl.w, "RIGHT")
        row.wcl   = col(APPLCOLS.wcl.x,   APPLCOLS.wcl.w, "RIGHT")
        row.icons = col(APPLCOLS.icons.x, APPLCOLS.icons.w)
        row:SetScript("OnLeave", function(self2) hideTip(); if self2.hover then self2.hover:Hide() end end)

        row.invite = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.invite:SetSize(56, 18)
        row.invite:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        row.invite:SetText("Invite")
        row.invite:SetNormalFontObject(GameFontNormalSmall)

        row.decline = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.decline:SetSize(20, 18)
        row.decline:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.decline:SetText("X")
        row.decline:SetNormalFontObject(GameFontNormalSmall)

        self.applBtns[i] = row
    end

    -- thin divider under the Applicants header
    self.applDivider = child:CreateTexture(nil, "ARTWORK")
    self.applDivider:SetColorTexture(0.3, 0.3, 0.35, 0.6)
    self.applDivider:SetHeight(1)
    self.applDivider:Hide()

    -- per-class "+N more / show fewer" expander toggles
    self.applExpanders = {}
    for i = 1, 12 do
        local e = CreateFrame("Button", nil, child)
        e:SetSize(150, 16)
        e.fs = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        e.fs:SetPoint("LEFT", 0, 0)
        e.fs:SetJustifyH("LEFT")
        e:SetScript("OnLeave", hideTip)
        e:Hide()
        self.applExpanders[i] = e
    end

    -- applicant column headers (drawn once above the list)
    self.applHead = {}
    for _, h in ipairs({ { k = "score", t = "M+" }, { k = "ilvl", t = "ilvl" }, { k = "wcl", t = "Key DPS" }, { k = "icons", t = "Brings" } }) do
        local fsh = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        -- numeric headers right-align over their right-aligned columns; "Brings" stays left
        if h.k == "icons" then
            fsh:SetJustifyH("LEFT")
        else
            fsh:SetWidth(APPLCOLS[h.k].w)
            fsh:SetJustifyH("RIGHT")
        end
        fsh:SetText(h.t)
        fsh:Hide()
        self.applHead[h.k] = fsh
    end

    -- info tab
    self.infoPrio = fs()
    self.infoNote = fs()
    self.infoCover = fs()
    self.infoNeed = fs()
    self.infoKey = fs()

    -- panel scale control (Info tab)
    self.scaleLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.scaleLabel:SetJustifyH("LEFT")
    local slider = CreateFrame("Slider", nil, child)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(180, 16)
    slider:SetMinMaxValues(0.7, 1.6)
    slider:SetValueStep(0.05)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    if thumb then thumb:SetSize(14, 18) end
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    track:SetHeight(4)
    track:SetPoint("LEFT", 2, 0)
    track:SetPoint("RIGHT", -2, 0)
    slider:SetScript("OnValueChanged", function(self2, val)
        val = math.floor(val * 20 + 0.5) / 20
        self2.pending = val
        if UI.scaleLabel then UI.scaleLabel:SetText("Panel scale: " .. math.floor(val * 100 + 0.5) .. "%") end
    end)
    slider:SetScript("OnMouseUp", function(self2)
        local val = self2.pending or self2:GetValue()
        ns.db.scale = val
        if UI.frame then UI.frame:SetScale(val) end
    end)
    self.scaleSlider = slider

    -- info-tab ability checklist rows
    self.infoRows = {}
    for i = 1, 16 do
        local s = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s:SetJustifyH("LEFT")
        s:SetWidth(childW - 2 * LX)
        s:SetWordWrap(false)
        self.infoRows[i] = s
    end

    -- "Advanced" disclosure toggle on the Coverage tab (folds in the old Info tab)
    self.advBtn = CreateFrame("Button", nil, child)
    self.advBtn:SetSize(childW - 2 * LX, 18)
    self.advBtn.fs = self.advBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.advBtn.fs:SetPoint("LEFT", 0, 0)
    self.advBtn.fs:SetJustifyH("LEFT")
    self.advBtn:SetScript("OnClick", function()
        ns.db.advCoverage = (not ns.db.advCoverage) or nil
        UI:Refresh()
    end)
    self.advBtn:Hide()

    self:UpdateTabs()
end

-- ------------------------------------------------------------- helpers ----
-- Normalize a name for matching: lowercase, strip everything but a-z0-9. Blizzard's
-- activity/instance strings rarely match our hand-entered dungeon names exactly
-- (apostrophe placement like Magister's vs Magisters', prefixes, punctuation), so
-- compare on the normalized form.
local function normName(s)
    if not s then return "" end
    return (s:lower():gsub("[^%w]", ""))
end

local function matchDungeonName(label)
    local nl = normName(label)
    if nl == "" then return nil end
    for _, key in ipairs(ns.Dungeons.order) do
        local dn = normName(ns.Dungeons.list[key].name)
        if dn ~= "" and (nl == dn or nl:find(dn, 1, true)) then return key end
    end
    return nil
end

function UI:DetectDungeon()
    -- inside the instance: match the instance name
    if IsInInstance and IsInInstance() and GetInstanceInfo then
        local byInst = matchDungeonName((GetInstanceInfo()))
        if byInst then return byInst end
    end
    -- forming a group: match the dungeon your Premade listing is for
    if C_LFGList and C_LFGList.GetActiveEntryInfo then
        local info = C_LFGList.GetActiveEntryInfo()
        local activityID = info and (info.activityID or (info.activityIDs and info.activityIDs[1]))
        if activityID and C_LFGList.GetActivityInfoTable then
            local act = C_LFGList.GetActivityInfoTable(activityID)
            if act then
                local byList = matchDungeonName(act.fullName or act.shortName)
                if byList then return byList end
            end
        end
    end
    return nil
end

-- /kc debug — dump what the auto-detector sees, so a missed match can be diagnosed.
function UI:Debug()
    local function p(...) print("|cff66ccffKeyComp|r", ...) end
    p("auto =", tostring(ns.db and ns.db.auto), "| selected =", tostring(ns.db and ns.db.dungeon))
    if GetInstanceInfo then
        local name, itype = GetInstanceInfo()
        p("instance:", tostring(name), "type:", tostring(itype), "| inInstance =", tostring(IsInInstance and IsInInstance()))
    end
    if C_LFGList and C_LFGList.GetActiveEntryInfo then
        local info = C_LFGList.GetActiveEntryInfo()
        if info then
            local aid = info.activityID or (info.activityIDs and info.activityIDs[1])
            p("active entry: activityID =", tostring(aid),
                "| activityIDs =", tostring(info.activityIDs and #info.activityIDs))
            if aid and C_LFGList.GetActivityInfoTable then
                local act = C_LFGList.GetActivityInfoTable(aid)
                if act then p("activity fullName =", tostring(act.fullName), "| shortName =", tostring(act.shortName)) end
            end
        else
            p("no active LFG entry (you must be the group's lister for listing-detect)")
        end
    end
    p("DetectDungeon() ->", tostring(self:DetectDungeon()))

    -- WCL data diagnostics
    if ns.WCL then
        p("WCL: loaded =", tostring(ns.WCL:IsLoaded()),
            "| region =", tostring(ns.WCL:PlayerRegion()), "| age =", ns.WCL:AgeText())
        local d = ns.WCLData or KeyCompWCL
        if d and d.chars then
            local total = 0
            for reg, bucket in pairs(d.chars) do
                local c = 0; for _ in pairs(bucket) do c = c + 1 end
                total = total + c
                p("  region", reg, "=", c, "chars")
            end
            p("  total chars =", total, "| generated =", tostring(d.generated))
        else
            p("  WCL data table is NIL \226\128\148 Data/WCLData.lua failed to load/compile")
        end
        -- live lookup test on the current applicants (shows exact name strings)
        local apps = (ns.Applicants and ns.Applicants.Read({}, self.dungeonKey)) or {}
        if #apps == 0 then
            p("  (no applicants to test lookup \226\128\148 run with a listing up)")
        end
        for i = 1, math.min(4, #apps) do
            local nm = apps[i].members[1] and apps[i].members[1].name
            local rec = nm and ns.WCL:Lookup(nm)
            p("  lookup [" .. tostring(nm) .. "] ->", rec and ("HIT bk=" .. (rec.bk or 0)) or "miss")
        end
    else
        p("WCL module not loaded (WCL.lua missing from .toc?)")
    end
end

function UI:CycleDungeon(delta)
    local order = ns.Dungeons.order
    local cur, idx = ns.db.dungeon, 1
    for i, k in ipairs(order) do if k == cur then idx = i break end end
    idx = idx + delta
    if idx < 1 then idx = #order elseif idx > #order then idx = 1 end
    ns.db.dungeon = order[idx]
    ns.db.auto = false
    self:Refresh()
end

function UI:SavePosition()
    local f = self.frame
    if not f then return end
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    ns.db.point = { left = left, top = top }
end

function UI:RestorePosition()
    local f = self.frame
    if not f then return end
    f:ClearAllPoints()
    local p = ns.db and ns.db.point
    if p and p.left and p.top then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
end

function UI:Show()
    if not self.frame then self:Init() end
    self.frame:Show()
    ns.db.shown = true
    self:Refresh()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
    ns.db.shown = false
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

function UI:UpdateTabs()
    if not self.tabs then return end
    local active = ns.db and ns.db.tab or "coverage"
    for _, b in ipairs(self.tabs) do
        if b.key == active then
            b.text:SetTextColor(1, 1, 1)
            b.underline:Show()
        else
            b.text:SetTextColor(0.6, 0.6, 0.6)
            b.underline:Hide()
        end
    end
end

function UI:UpdateScrollHint()
    local s = self.scroll
    if not s or not self.scrollHint then return end
    local range = math.max(0, (s.contentHeight or 0) - s:GetHeight())
    if range > 1 and s:GetVerticalScroll() < range - 1 then
        self.scrollHint:Show()
    else
        self.scrollHint:Hide()
    end
end

function UI:HideAllTabs()
    for i = 1, 7 do self.cells[i]:Hide(); self.cells[i].label:Hide() end
    if self.utilCells then for i = 1, 3 do self.utilCells[i]:Hide(); self.utilCells[i].label:Hide() end end
    if self.roleSlots then for i = 1, 5 do self.roleSlots[i]:Hide() end end
    self.h_group:Hide()
    for i = 1, 5 do self.memberBtns[i]:Hide() end
    self.utilText:Hide(); self.gapsText:Hide()
    if self.buffsText then self.buffsText:Hide() end
    self.h_appl:Hide(); self.applEmpty:Hide()
    for i = 1, APPL_MAX_ROWS do self.applBtns[i]:Hide() end
    if self.applHead then for _, h in pairs(self.applHead) do h:Hide() end end
    for i = 1, 3 do self.applSecHeaders[i]:Hide(); self.applBoxes[i]:Hide() end
    if self.applDivider then self.applDivider:Hide() end
    if self.applExpanders then for _, e in ipairs(self.applExpanders) do e:Hide() end end
    self.infoPrio:Hide(); self.infoNote:Hide(); self.infoCover:Hide()
    self.infoNeed:Hide(); self.infoKey:Hide()
    if self.scaleSlider then self.scaleSlider:Hide() end
    if self.scaleLabel then self.scaleLabel:Hide() end
    if self.infoRows then for i = 1, 16 do self.infoRows[i]:Hide() end end
    if self.advBtn then self.advBtn:Hide() end
end

-- --------------------------------------------------------------- tooltips --
function UI:CoverageTip(owner, t, info, dungeon)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(C.LABELS[t] or t, 1, 1, 1)
    local sc = STATUS[info.status]
    local label = (info.status == "covered" and "Covered")
        or (info.status == "maybe" and "Maybe (spec/talent unconfirmed)")
        or "MISSING"
    GameTooltip:AddLine(label, sc[1], sc[2], sc[3])
    if #info.by > 0 then GameTooltip:AddLine("By: " .. plainNames(info.by), 0.6, 0.9, 0.6, true) end
    if #info.maybeBy > 0 then GameTooltip:AddLine("Maybe: " .. plainNames(info.maybeBy), 0.9, 0.8, 0.3, true) end
    if info.status ~= "covered" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Bring: " .. (ns.Recommend.providerText[t] or "?"), 0.8, 0.8, 0.8, true)
    end
    if info.required then GameTooltip:AddLine("Required for " .. dungeon.name, 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
end

function UI:UtilTip(owner, d)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(C.LABELS[d.key] or d.label, 1, 1, 1)
    local sc = STATUS[d.status]
    local txt = (d.status == "covered" and "Covered") or (d.status == "maybe" and "Partial") or "MISSING"
    if d.key == "shortkick" then
        txt = d.n .. " short kick" .. (d.n == 1 and "" or "s") .. "  (want 2)"
    end
    GameTooltip:AddLine(txt, sc[1], sc[2], sc[3])
    if d.by and #d.by > 0 then GameTooltip:AddLine("By: " .. plainNames(d.by), 0.6, 0.9, 0.6, true) end
    if d.maybeBy and #d.maybeBy > 0 then GameTooltip:AddLine("Maybe: " .. plainNames(d.maybeBy), 0.9, 0.8, 0.3, true) end
    GameTooltip:Show()
end

function UI:MemberTip(owner, entry)
    local m = entry.m
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText((m.name or "?") .. (m.isPlayer and " (you)" or ""), classColorRGB(m.class))
    local sub = (m.spec and (m.spec .. " ") or "") .. (ROLE_DISPLAY[m.role] or m.role or "")
    if sub ~= "" then GameTooltip:AddLine(sub, 0.8, 0.8, 0.8) end
    local conf, maybe = {}, {}
    for _, t in ipairs(CAP_ORDER) do
        if entry.conf[t] then conf[#conf + 1] = C.LABELS[t]
        elseif entry.pot[t] then maybe[#maybe + 1] = C.LABELS[t] end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Provides: " .. (#conf > 0 and table.concat(conf, ", ") or "nothing tracked"), 0.6, 0.9, 0.6, true)
    if #maybe > 0 then GameTooltip:AddLine("Maybe: " .. table.concat(maybe, ", "), 0.9, 0.8, 0.3, true) end
    if not m.isPlayer and ns.WCL and ns.WCL:IsLoaded() then
        local rec = ns.WCL:Lookup(m.name)
        if rec then
            local stat = ns.WCL:DungeonStat(rec, self.dungeonKey)
            if stat then
                GameTooltip:AddLine(("WCL: +%d  %s dps %s"):format(stat.k or 0, ns.WCL.FmtDps(stat.dps), ns.WCL.MedalText(stat.md)), 0.70, 0.54, 1.0)
            end
            local best = ns.WCL:BestEntry(rec)
            if best and best.dungeon ~= self.dungeonKey then
                local bdn = (ns.Dungeons.list[best.dungeon] and ns.Dungeons.list[best.dungeon].name) or best.dungeon
                GameTooltip:AddLine(("WCL best: +%d  %s dps  %s"):format(best.k or 0, ns.WCL.FmtDps(best.dps), bdn), 0.55, 0.45, 0.8)
            end
        end
    end
    GameTooltip:Show()
end

-- Append a per-dungeon WCL breakdown to the tooltip: every OTHER dungeon this char
-- has logged (highest key + the dps from that run), best key first. Mirrors the
-- site's per-dungeon DPS table so a hover shows the player's whole M+ picture, not
-- just the selected dungeon. (We bake only the best key per dungeon, so this is one
-- row per dungeon, not every individual key run.)
local function wclBreakdown(rec, selectedKey)
    if not (rec and rec.d) then return end
    local rows = {}
    for dk, s in pairs(rec.d) do
        if dk ~= selectedKey then
            rows[#rows + 1] = { dk = dk, k = s.k or 0, dps = s.dps or 0 }
        end
    end
    if #rows == 0 then return end
    table.sort(rows, function(a, b)
        if a.k ~= b.k then return a.k > b.k end
        return a.dps > b.dps
    end)
    GameTooltip:AddLine(("Other logged dungeons (%d):"):format(#rows), 0.6, 0.6, 0.65)
    for _, row in ipairs(rows) do
        local dname = (ns.Dungeons.list[row.dk] and ns.Dungeons.list[row.dk].name) or row.dk
        GameTooltip:AddDoubleLine(dname, ("+%d   %s"):format(row.k, ns.WCL.FmtDps(row.dps)),
            0.62, 0.62, 0.68, 0.80, 0.74, 0.92)
    end
end

function UI:ApplicantTip(owner, app)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(app.isGroup and "Applicant GROUP" or "Applicant", 1, 1, 1)
    if app.isGroup then
        GameTooltip:AddLine("Inviting accepts ALL " .. #app.members .. " members", 1, 0.63, 0.13, true)
    end
    for _, m in ipairs(app.members) do
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((m.name or "?"), classColorRGB(m.class))
        -- spec + role line (spec is only present where the API/demo supplies it)
        local sr = {}
        if m.spec and m.spec ~= "" then sr[#sr + 1] = m.spec end
        sr[#sr + 1] = (ROLE_DISPLAY[m.role] or m.role or "?")
        GameTooltip:AddLine(classColored(m.class) .. GREY .. "  \194\183  " .. table.concat(sr, " \194\183 ") .. R, 0.7, 0.7, 0.7)
        local il = (m.ilvl and m.ilvl > 0) and ("ilvl " .. math.floor(m.ilvl)) or ""
        local mp = (m.score and m.score > 0) and ("M+ " .. m.score) or ""
        if il ~= "" or mp ~= "" then
            local r, g, bcol = scoreRGB(m.score)
            GameTooltip:AddDoubleLine(il, mp, 0.85, 0.85, 0.85, r, g, bcol)
        end
        if m.relationship and m.relationship ~= "" then
            GameTooltip:AddLine("note: " .. m.relationship, 0.45, 0.8, 0.45, true)
        end
        if ns.WCL and ns.WCL:IsLoaded() then
            local rec = ns.WCL:Lookup(m.name)
            if rec then
                local dn = (ns.Dungeons.list[self.dungeonKey] and ns.Dungeons.list[self.dungeonKey].name) or "this key"
                local stat = ns.WCL:DungeonStat(rec, self.dungeonKey)
                if stat then
                    GameTooltip:AddLine(("WCL %s: +%d  %s dps  (score %d) %s"):format(
                        dn, stat.k or 0, ns.WCL.FmtDps(stat.dps), stat.sc or 0, ns.WCL.MedalText(stat.md)), 0.70, 0.54, 1.0)
                else
                    GameTooltip:AddLine(("WCL: no %s log"):format(dn), 0.55, 0.5, 0.62)
                end
                wclBreakdown(rec, self.dungeonKey)
            end
        end
    end
    GameTooltip:AddLine(" ")
    if #app.fills > 0 then
        local labels = {}
        for _, t in ipairs(app.fills) do labels[#labels + 1] = C.LABELS[t] or t end
        GameTooltip:AddLine("Fills gaps: " .. table.concat(labels, ", "), 0.6, 0.9, 0.6, true)
    else
        GameTooltip:AddLine("Fills no current gaps", 0.7, 0.7, 0.7)
    end
    if ns.WCL and ns.WCL:IsLoaded() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("WCL M+ data " .. ns.WCL:AgeText() .. " \226\128\162 top-ladder only", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-- --------------------------------------------------------------- renderers --
local function buildNeeds(cov)
    local u = cov.utility
    local needs = {}
    for t in pairs(cov.missing) do needs[t] = true end
    if #u.kick.conf < 2 then needs.shortkick = true end
    if #u.lust.conf < 1 then needs.lust = true end
    if #u.battlerez.conf < 1 then needs.battlerez = true end
    return needs
end

-- missing raid buffs as "<class icon> Name" tokens (shows which class brings each).
local function missingBuffTokens(cov)
    local t = {}
    for _, b in ipairs(cov.buffs or {}) do
        if not b.have then
            t[#t + 1] = classIconInline(b.class, 12) .. " " .. b.name
        end
    end
    return t
end

-- group a role list by class -> top 3 applicants per class (by priority).
-- classes ordered by gaps filled, then the class's best applicant priority.
local function classGroups(list)
    local byClass, order = {}, {}
    for _, app in ipairs(list) do
        local cls = (app.members[1] and app.members[1].class) or "?"
        local g = byClass[cls]
        if not g then
            g = { class = cls, apps = {}, fills = app.fills }
            byClass[cls] = g
            order[#order + 1] = g
        end
        g.apps[#g.apps + 1] = app
    end
    for _, g in ipairs(order) do
        table.sort(g.apps, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
        g.count = #g.apps
        g.best = (g.apps[1] and g.apps[1].priority) or 0
    end
    table.sort(order, function(a, b)
        if #a.fills ~= #b.fills then return #a.fills > #b.fills end
        return a.best > b.best
    end)
    return order
end

-- coverage status strip (shared by Coverage + Applicants tabs)
function UI:RenderStrip(y)
    local cov, dungeon = self.cov, self.dungeon
    local order = {}
    for _, t in ipairs(C.REMOVAL_ORDER) do if cov.removal[t] then order[#order + 1] = t end end
    local x = LX
    for i = 1, 7 do
        local t = order[i]
        local cell = self.cells[i]
        if t then
            local info = cov.removal[t]
            local col = STATUS[info.status]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", x, -y)
            cell.bg:SetColorTexture(col[1], col[2], col[3], 0.95)
            cell.icon:SetTexture(REMOVAL_ICON[t] or "Interface\\Icons\\INV_Misc_QuestionMark")
            cell.icon:SetDesaturated(info.status == "missing")
            cell.label:SetText(REMOVAL_SHORT[t] or t)
            cell.label:SetTextColor(col[1] + 0.25, col[2] + 0.25, col[3] + 0.25)
            cell:SetScript("OnEnter", function(b) UI:CoverageTip(b, t, info, dungeon) end)
            cell:Show(); cell.label:Show()
            x = x + 44
        else
            cell:Hide(); cell.label:Hide()
        end
    end

    -- utility cells, right-aligned: kicks (count -> green/yellow/red), lust, rez.
    local u = cov.utility
    local kick = #u.kick.conf
    local udef = {
        { key = "shortkick", label = "Kick", icon = FILL_ICON.shortkick,
          status = (kick >= 2 and "covered") or (kick == 1 and "maybe") or "missing",
          n = kick, by = u.kick.conf, maybeBy = u.kick.maybe },
        { key = "lust", label = "Lust", icon = FILL_ICON.lust,
          status = (#u.lust.conf > 0 and "covered") or "missing",
          n = #u.lust.conf, by = u.lust.conf, maybeBy = u.lust.maybe },
        { key = "battlerez", label = "Rez", icon = FILL_ICON.battlerez,
          status = (#u.battlerez.conf > 0 and "covered") or "missing",
          n = #u.battlerez.conf, by = u.battlerez.conf, maybeBy = u.battlerez.maybe },
    }
    local ux = self.childW - LX - 38 - 2 * 44  -- leftmost of the 3 right-aligned cells
    for j = 1, 3 do
        local d = udef[j]
        local cell = self.utilCells[j]
        local col = STATUS[d.status]
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", ux + (j - 1) * 44, -y)
        cell.bg:SetColorTexture(col[1], col[2], col[3], 0.95)
        cell.icon:SetTexture(d.icon)
        cell.icon:SetDesaturated(d.status == "missing")
        cell.label:SetText(d.key == "shortkick" and (d.label .. " " .. d.n) or d.label)
        cell.label:SetTextColor(col[1] + 0.25, col[2] + 0.25, col[3] + 0.25)
        cell:SetScript("OnEnter", function(b) UI:UtilTip(b, d) end)
        cell:Show(); cell.label:Show()
    end
    return y + 38 + 18
end

-- utility line + gaps + missing buffs (shared by Coverage + Applicants tabs)
function UI:RenderUtilGapsBuffs(y)
    local cov = self.cov
    local u = cov.utility
    local kick = #u.kick.conf
    local kcol = (kick >= 2 and GREEN) or (kick == 1 and YELLOW) or RED
    local longStr = (#u.longkick > 0) and (GREY .. " +" .. #u.longkick .. " long" .. R) or ""
    local lust = (#u.lust.conf > 0) and (GREEN .. "YES" .. R) or (RED .. "NO" .. R)
    local rez = (#u.battlerez.conf > 0) and (GREEN .. "YES" .. R) or (RED .. "NO" .. R)
    self.utilText:ClearAllPoints(); self.utilText:SetPoint("TOPLEFT", LX, -y)
    self.utilText:SetText("Kicks " .. kcol .. kick .. R .. longStr .. "    " .. GREY .. "|" .. R ..
        "    Lust " .. lust .. "    " .. GREY .. "|" .. R .. "    Battle rez " .. rez)
    self.utilText:Show(); y = y + 20

    local gaps = {}
    for t in pairs(cov.missing) do gaps[#gaps + 1] = C.LABELS[t] or t end
    if kick < 2 then gaps[#gaps + 1] = "2nd Kick" end
    if #u.lust.conf < 1 then gaps[#gaps + 1] = "Lust" end
    if #u.battlerez.conf < 1 then gaps[#gaps + 1] = "Battle Rez" end
    self.gapsText:ClearAllPoints(); self.gapsText:SetPoint("TOPLEFT", LX, -y)
    if #gaps > 0 then
        self.gapsText:SetText(RED .. "Gaps: " .. R .. table.concat(gaps, ", "))
    else
        self.gapsText:SetText(GREEN .. "No gaps \226\128\148 comp is fully covered." .. R)
    end
    self.gapsText:Show(); y = y + self.gapsText:GetStringHeight() + 6

    local mb = missingBuffTokens(cov)
    self.buffsText:ClearAllPoints(); self.buffsText:SetPoint("TOPLEFT", LX, -y)
    if #mb > 0 then
        self.buffsText:SetText(YELLOW .. "Buffs missing: " .. R .. table.concat(mb, "   "))
    else
        self.buffsText:SetText(GREEN .. "All raid buffs covered" .. R)
    end
    self.buffsText:Show(); y = y + self.buffsText:GetStringHeight() + 6

    return y
end

-- minimalist quick recap: ability strip (red = gap) + big utility + the group
-- roster, with everything detailed folded behind the Advanced toggle.
function UI:RenderCoverage()
    local cov, roster = self.cov, self.roster
    local y = 4
    y = self:RenderStrip(y)

    -- role-composition recap (icons): ideal 1 tank / 1 heal / 3 dps, lit = filled
    local nTank, nHeal, nDps = 0, 0, 0
    for _, e in ipairs(cov.resolved) do
        local role = e.m.role
        if role == "TANK" then nTank = nTank + 1
        elseif role == "HEALER" then nHeal = nHeal + 1
        elseif role == "DAMAGER" then nDps = nDps + 1 end
    end
    local slots = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }
    local fillBy = { TANK = nTank, HEALER = nHeal, DAMAGER = nDps }
    local usedBy = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    local sx = LX
    for i = 1, 5 do
        local role = slots[i]
        local tex = self.roleSlots[i]
        tex:SetAtlas(ROLE_ATLAS[role])
        usedBy[role] = usedBy[role] + 1
        local filled = usedBy[role] <= fillBy[role]
        tex:SetDesaturated(not filled)
        tex:SetAlpha(filled and 1 or 0.3)
        tex:ClearAllPoints(); tex:SetPoint("TOPLEFT", sx, -y)
        tex:Show()
        sx = sx + 24
    end
    y = y + 26
    for i = 1, 5 do
        local b = self.memberBtns[i]
        local entry = cov.resolved[i]
        if entry then
            local m = entry.m
            -- ilvl / score / spec: you = live APIs; party = what we cached when they
            -- applied (the game won't hand it over once they've joined), else a
            -- roster-supplied value (demo).
            local ilvl, score, spec
            if m.isPlayer then
                local _, eq = GetAverageItemLevel()
                ilvl = eq
                score = C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore()
                spec = m.spec
            else
                local sd = ns.Applicants and ns.Applicants.SignupData and ns.Applicants.SignupData(m.name)
                ilvl = m.ilvl or (sd and sd.ilvl)
                score = m.score or (sd and sd.score)
                spec = m.spec or (sd and sd.spec)
            end
            b.text:SetText(ccName(m) .. (spec and ("   " .. GREY .. spec .. R) or ""))
            b.ilvl:SetText((ilvl and ilvl > 0) and (ilvlColorCode(ilvl) .. math.floor(ilvl + 0.5) .. R) or "")
            b.score:SetText((score and score > 0) and (scoreColorCode(score) .. score .. R) or "")
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", LX, -y)
            b:SetScript("OnEnter", function(btn) UI:MemberTip(btn, entry) end)
            b:Show(); y = y + 15
        else
            b:Hide()
        end
    end
    y = y + 8

    -- divider
    self.applDivider:ClearAllPoints()
    self.applDivider:SetPoint("TOPLEFT", LX, -y + 3)
    self.applDivider:SetPoint("TOPRIGHT", self.child, "TOPLEFT", self.childW - LX, -y + 3)
    self.applDivider:Show()
    y = y + 10

    -- Advanced disclosure (folds in the old Info tab: who-covers-each-cast, notes,
    -- missing buffs, scale)
    local open = ns.db.advCoverage
    local plus  = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14:0:0|t"
    local minus = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14:0:0|t"
    self.advBtn.fs:SetText((open and minus or plus) .. " " .. WHITE .. "Advanced" .. R
        .. "  " .. GREY .. "who covers each cast \194\183 notes \194\183 buffs" .. R)
    self.advBtn:ClearAllPoints(); self.advBtn:SetPoint("TOPLEFT", LX, -y)
    self.advBtn:Show(); y = y + 22

    if open then
        y = self:RenderAdvanced(y)
    end
    return y
end

-- WCL compact cell for an applicant member: "+key dps" for the SELECTED dungeon
-- (purple); else their best logged "+key dps" in any dungeon (grey); else "".
local function wclCell(m, dungeonKey)
    if not (ns.WCL and ns.WCL:IsLoaded() and m and m.name) then return "" end
    local rec = ns.WCL:Lookup(m.name)
    if not rec then return "" end
    -- "+key dps" for the selected dungeon (purple) = highest key they've logged in
    -- it + the dps from that run; else their best "+key dps" any dungeon (grey).
    -- "+key dps": the +key keeps its context color (purple = selected dungeon,
    -- grey = best elsewhere); the dps number is tinted by WCL medal band.
    local stat = ns.WCL:DungeonStat(rec, dungeonKey)
    if stat and stat.dps and stat.dps > 0 then
        return WCLC .. "+" .. (stat.k or 0) .. " " .. R .. (MEDAL_CODE[stat.md] or WCLC) .. ns.WCL.FmtDps(stat.dps) .. R
    end
    local best = ns.WCL:BestEntry(rec)
    if best and best.dps and best.dps > 0 then
        return GREY .. "+" .. (best.k or 0) .. " " .. R .. (MEDAL_CODE[best.md] or GREY) .. ns.WCL.FmtDps(best.dps) .. R
    end
    if rec.bk and rec.bk > 0 then
        return GREY .. "+" .. rec.bk .. R
    end
    return ""
end

-- one compact applicant row. primary = the class's top pick (full class icon);
-- alternates (shown only when the class is expanded) get a small indent + icon.
-- invited rows disable the Invite button. Returns the next y.
function UI:SetupApplicantRow(b, app, primary, y)
    local m = app.members[1]
    local appID = app.applicantID
    local invited = app.invited or (UI.invitedLocal and UI.invitedLocal[appID]) or false

    -- premade tag: one Invite pulls the whole group; members are nested below.
    local groupTag = app.isGroup and ("  |cffffa020\194\183 GRP " .. #app.members .. R) or ""
    -- in a premade, show each member's role icon next to their class
    local roleIcon = app.isGroup and roleIconInline(m.role, primary and 14 or 13) or ""
    if primary then
        b.name:SetText(classIconInline(m.class) .. roleIcon .. ccName(m) .. groupTag)
    else
        b.name:SetText("   " .. classIconInline(m.class, 14) .. roleIcon .. ccName(m) .. groupTag)
    end

    b.icons:SetText(fillIconsInline(app.fills))
    b.score:SetText((m.score and m.score > 0) and (scoreColorCode(m.score) .. m.score .. R) or "")
    b.ilvl:SetText((m.ilvl and m.ilvl > 0) and (ilvlColorCode(m.ilvl) .. math.floor(m.ilvl + 0.5) .. R) or "")
    b.wcl:SetText(wclCell(m, self.dungeonKey))

    b:ClearAllPoints(); b:SetPoint("TOPLEFT", LX + 4, -y)
    b:SetScript("OnEnter", function(btn) if btn.hover then btn.hover:Show() end; UI:ApplicantTip(btn, app) end)
    if b.hl then if invited then b.hl:Show() else b.hl:Hide() end end

    if invited then b.invite:SetText("Invited"); b.invite:Disable()
    else b.invite:SetText("Invite"); b.invite:Enable() end
    b.invite:SetScript("OnClick", function(self2)
        if C_LFGList and C_LFGList.InviteApplicant then C_LFGList.InviteApplicant(appID) end
        UI.invitedLocal[appID] = true
        self2:SetText("Invited"); self2:Disable()
        if b.hl then b.hl:Show() end
        if C_Timer then C_Timer.After(0.3, function() UI:Refresh() end) end
    end)
    b.decline:SetScript("OnClick", function()
        UI.invitedLocal[appID] = nil
        if C_LFGList and C_LFGList.DeclineApplicant then C_LFGList.DeclineApplicant(appID) end
        if C_Timer then C_Timer.After(0.3, function() UI:Refresh() end) end
    end)
    b.invite:Show(); b.decline:Show()
    b:Show()
    return y + (primary and 20 or 18)
end

-- a nested premade-member row under its leader: identity + stats only, no Invite
-- (the leader's Invite accepts the whole group). Hovering shows the group tip.
function UI:SetupMemberRow(b, app, member, y)
    -- nested under the leader: indent + a dim middle-dot marker (the U+21B3 hook
    -- arrow used before is tofu in WoW's default font)
    b.name:SetText("       " .. GREY .. "\194\183  " .. R .. classIconInline(member.class, 14) .. roleIconInline(member.role, 13) .. ccName(member))
    b.icons:SetText("")
    b.score:SetText((member.score and member.score > 0) and (scoreColorCode(member.score) .. member.score .. R) or "")
    b.ilvl:SetText((member.ilvl and member.ilvl > 0) and (ilvlColorCode(member.ilvl) .. math.floor(member.ilvl + 0.5) .. R) or "")
    b.wcl:SetText(wclCell(member, self.dungeonKey))

    b:ClearAllPoints(); b:SetPoint("TOPLEFT", LX + 4, -y)
    b:SetScript("OnEnter", function(btn) if btn.hover then btn.hover:Show() end; UI:ApplicantTip(btn, app) end)
    if b.hl then b.hl:Hide() end
    b.invite:Hide(); b.decline:Hide()
    b:Show()
    return y + 18
end

-- the "+N more / show fewer" toggle under a class group. Returns the next y.
function UI:SetupExpander(e, ckey, hidden, expanded, y)
    local plus  = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14:0:0|t"
    local minus = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14:0:0|t"
    if expanded then
        e.fs:SetText(minus .. " " .. GREY .. "show fewer" .. R)
    else
        e.fs:SetText(plus .. " |cff7d9dff" .. hidden .. " more" .. R)
    end
    e:ClearAllPoints(); e:SetPoint("TOPLEFT", LX + 4 + APPLCOLS.name.x + 20, -y)
    e:SetScript("OnClick", function()
        UI.expandedClasses[ckey] = (not UI.expandedClasses[ckey]) or nil
        UI:Refresh()
    end)
    e:Show()
    return y + 16
end

-- merged-coverage Applicants header: the dungeon ability strip (as on the
-- Coverage tab), then a big, prominent kicks/lust/rez row, then a divider. No
-- global count -- per-role counts live on the section headers.
-- merged-coverage Applicants header: ability strip (incl. utility cells) + divider.
function UI:RenderApplicantHeader(y)
    y = self:RenderStrip(y)

    self.applDivider:ClearAllPoints()
    self.applDivider:SetPoint("TOPLEFT", LX, -y + 3)
    self.applDivider:SetPoint("TOPRIGHT", self.child, "TOPLEFT", self.childW - LX, -y + 3)
    self.applDivider:Show()
    y = y + 8

    return y
end

function UI:RenderApplicants()
    local cov = self.cov
    local y = 4
    local needs = buildNeeds(cov)
    local apps = (ns.Applicants and ns.Applicants.Read(needs, self.dungeonKey)) or {}

    y = self:RenderApplicantHeader(y)

    if #apps == 0 then
        local msg = (ns.Applicants and ns.Applicants.HasListing())
            and "Listing active \226\128\148 waiting for applicants\226\128\166"
            or "Post a Premade Group listing to score applicants here."
        self.applEmpty:ClearAllPoints(); self.applEmpty:SetPoint("TOPLEFT", LX, -y)
        self.applEmpty:SetText(GREY .. msg .. R)
        self.applEmpty:Show(); y = y + 18
        for i = 1, APPL_MAX_ROWS do self.applBtns[i]:Hide() end
        for i = 1, 3 do self.applSecHeaders[i]:Hide(); self.applBoxes[i]:Hide() end
        for _, e in ipairs(self.applExpanders) do e:Hide() end
        return y
    end
    self.applEmpty:Hide()

    local groups = { TANK = {}, DAMAGER = {}, OTHER = {} }
    for _, app in ipairs(apps) do
        local role = app.members[1] and app.members[1].role
        if role == "TANK" then groups.TANK[#groups.TANK + 1] = app
        elseif role == "DAMAGER" then groups.DAMAGER[#groups.DAMAGER + 1] = app
        else groups.OTHER[#groups.OTHER + 1] = app end
    end
    local sectionDefs = {
        { key = "TANK",    label = "TANKS",           accent = { 0.32, 0.58, 0.96 } },
        { key = "DAMAGER", label = "DPS",             accent = { 0.90, 0.45, 0.40 } },
        { key = "OTHER",   label = "Healers / Other", accent = { 0.40, 0.78, 0.50 } },
    }

    -- aligned column headers so the rows read as a table
    for _, key in ipairs({ "score", "ilvl", "wcl", "icons" }) do
        local h = self.applHead[key]
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", LX + 4 + APPLCOLS[key].x, -y)
        h:Show()
    end
    y = y + 13

    -- render one applicant row and, if it's a premade, its members nested below.
    -- ri / y are upvalues so this stays in step with the section loop.
    local ri = 0
    local function renderApplicant(app, primary)
        if ri >= APPL_MAX_ROWS then return end
        ri = ri + 1
        y = self:SetupApplicantRow(self.applBtns[ri], app, primary, y)
        if app.isGroup then
            for mi = 2, #app.members do
                if ri >= APPL_MAX_ROWS then break end
                ri = ri + 1
                y = self:SetupMemberRow(self.applBtns[ri], app, app.members[mi], y)
            end
        end
    end

    local si, ei = 0, 0
    for _, def in ipairs(sectionDefs) do
        local cgroups = classGroups(groups[def.key])
        if #cgroups > 0 then
            si = si + 1
            local secHeader = self.applSecHeaders[si]
            secHeader:ClearAllPoints(); secHeader:SetPoint("TOPLEFT", LX, -y)
            secHeader:SetText("|cff" .. rgbHex(def.accent) .. def.label .. R
                .. "  " .. WHITE .. #groups[def.key] .. R)
            secHeader:Show()
            y = y + 16

            local boxTop = y - 1
            for _, g in ipairs(cgroups) do
                if ri >= APPL_MAX_ROWS then break end
                local ckey = def.key .. ":" .. g.class
                local expanded = UI.expandedClasses[ckey]
                local showN = expanded and #g.apps or 1
                for idx = 1, showN do
                    if ri >= APPL_MAX_ROWS then break end
                    renderApplicant(g.apps[idx], idx == 1)
                end
                -- only offer the toggle when there's more than the one top pick
                if #g.apps > 1 and ei < #self.applExpanders then
                    ei = ei + 1
                    y = self:SetupExpander(self.applExpanders[ei], ckey, #g.apps - 1, expanded, y)
                end
            end
            local boxBottom = y + 1

            local box = self.applBoxes[si]
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", 2, -boxTop)
            box:SetSize(self.childW - 4, boxBottom - boxTop)
            box:SetBackdropBorderColor(def.accent[1], def.accent[2], def.accent[3], 0.9)
            box:Show()

            y = y + 10
        end
    end

    for i = ri + 1, APPL_MAX_ROWS do self.applBtns[i]:Hide() end
    for i = si + 1, 3 do self.applSecHeaders[i]:Hide(); self.applBoxes[i]:Hide() end
    for i = ei + 1, #self.applExpanders do self.applExpanders[i]:Hide() end
    return y
end

-- the folded-in Info content (advanced disclosure on the Coverage tab): dispel
-- load, dungeon note, missing buffs, who-covers-each-cast, scale. Returns next y.
function UI:RenderAdvanced(y)
    local d = self.dungeon

    local cov = self.cov
    local pm = cov and cov.player and cov.player.m
    local pconf = (cov and cov.player and cov.player.conf) or {}

    -- ---- YOUR JOB: what your spec is on the hook for in this dungeon ----
    local pcol = PRIORITY_COLOR[d.priority] or WHITE
    local who = pm and (classColored(pm.class) .. (pm.spec and (GREY .. "  " .. pm.spec .. R) or "")) or (GREY .. "you" .. R)
    self.infoPrio:ClearAllPoints(); self.infoPrio:SetPoint("TOPLEFT", LX, -y)
    self.infoPrio:SetText(WHITE .. "YOUR JOB" .. R .. "   " .. who
        .. GREY .. "     \194\183  dungeon load " .. R .. pcol .. (d.priority or "?") .. R)
    self.infoPrio:Show(); y = y + 20

    -- removal types this dungeon demands that YOUR spec can dispel, + interrupt
    local jobs = {}
    for _, t in ipairs(C.REMOVAL_ORDER) do
        if cov and cov.relevant and cov.relevant[t] and pconf[t] then
            local ic = FILL_ICON[t]
            jobs[#jobs + 1] = (ic and ("|T" .. ic .. ":16:16:0:0|t ") or "") .. (C.LABELS[t] or t)
        end
    end
    local hasKick = false
    for _, a in ipairs(d.abilities or {}) do if a.kick then hasKick = true; break end end
    if hasKick and (pconf.shortkick or pconf.interrupt) then
        jobs[#jobs + 1] = "|T" .. FILL_ICON.shortkick .. ":16:16:0:0|t Interrupt"
    end
    self.infoNeed:ClearAllPoints(); self.infoNeed:SetPoint("TOPLEFT", LX, -y)
    if #jobs > 0 then
        self.infoNeed:SetText("    " .. GREEN .. table.concat(jobs, "      ") .. R)
    else
        self.infoNeed:SetText("    " .. GREY .. "Nothing here needs your dispels \226\128\148 focus dps / hps / kicks." .. R)
    end
    self.infoNeed:Show(); y = y + self.infoNeed:GetStringHeight() + 8

    if d.note and d.note ~= "" then
        self.infoNote:ClearAllPoints(); self.infoNote:SetPoint("TOPLEFT", LX, -y)
        self.infoNote:SetText(GREY .. d.note .. R)
        self.infoNote:Show(); y = y + self.infoNote:GetStringHeight() + 10
    else
        self.infoNote:Hide()
    end

    -- ---- EVERY CAST: who handles each dangerous cast ----
    self.infoCover:ClearAllPoints(); self.infoCover:SetPoint("TOPLEFT", LX, -y)
    self.infoCover:SetText(WHITE .. "EVERY CAST" .. R .. "   " .. OK_ICON .. GREY .. " covered  \194\183  " .. R .. NO_ICON .. GREY .. " gap" .. R)
    self.infoCover:Show(); y = y + 18

    local resolved = (cov and cov.resolved) or {}
    -- Who in the LIVE group handles this cast: kick it (if kickable) else dispel its
    -- type. Class-coloured first names; solo this is just you, and it fills in with
    -- real names/classes as the group forms.
    local function handlersFor(a)
        local names = {}
        for _, r in ipairs(resolved) do
            local can = (a.kick and (r.conf.shortkick or r.conf.interrupt)) or ((not a.kick) and r.conf[a.t])
            if can then
                local nm = r.m.isPlayer and "You" or (((r.m.name or "?"):match("^[^-]+")) or r.m.name or "?")
                local cs = classColorStr(r.m.class)
                names[#names + 1] = (cs and ("|c" .. cs .. nm .. R)) or nm
            end
        end
        return names
    end

    local n = 0
    for _, a in ipairs(d.abilities or {}) do
        if n >= 16 then break end
        n = n + 1
        local row = self.infoRows[n]
        local handlers = handlersFor(a)
        local covered = #handlers > 0
        -- lead with a scannable status mark; one type icon (dispel type, or kick
        -- icon for interrupts); no boss-name text (that was the clutter).
        local mark = covered and OK_ICON or NO_ICON
        local typeIcon = FILL_ICON[a.t] or (a.kick and FILL_ICON.shortkick) or nil
        local iconStr = typeIcon and ("|T" .. typeIcon .. ":15:15:0:0|t ") or ""
        local abCol = covered and WHITE or "|cffffb0b0"
        local right
        if covered then
            right = table.concat(handlers, GREY .. ", " .. R)
        else
            right = RED .. "needs " .. (a.kick and "interrupt" or (C.LABELS[a.t] or a.t)) .. R
        end
        row:SetText(mark .. "  " .. iconStr .. abCol .. a.ab .. R .. "    " .. right)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", LX, -y)
        row:Show(); y = y + 16
    end
    for i = n + 1, 16 do self.infoRows[i]:Hide() end
    y = y + 14

    -- ---- RAID BUFFS & DEBUFFS: clear have (green check) / missing (red x) ----
    self.infoKey:ClearAllPoints(); self.infoKey:SetPoint("TOPLEFT", LX, -y)
    self.infoKey:SetText(WHITE .. "RAID BUFFS & DEBUFFS" .. R)
    self.infoKey:Show(); y = y + 18
    local btoks = {}
    for _, b in ipairs(cov.buffs or {}) do
        local bm = b.have and OK_ICON or NO_ICON
        local bc = b.have and WHITE or "|cffff8080"
        btoks[#btoks + 1] = bm .. classIconInline(b.class, 13) .. bc .. b.name .. R
    end
    self.buffsText:ClearAllPoints(); self.buffsText:SetPoint("TOPLEFT", LX, -y)
    self.buffsText:SetText("    " .. table.concat(btoks, "     "))
    self.buffsText:Show(); y = y + self.buffsText:GetStringHeight() + 12

    self.scaleLabel:ClearAllPoints(); self.scaleLabel:SetPoint("TOPLEFT", LX, -y)
    self.scaleLabel:SetText("Panel scale: " .. math.floor((ns.db.scale or 1) * 100 + 0.5) .. "%")
    self.scaleLabel:Show(); y = y + 18
    self.scaleSlider:ClearAllPoints(); self.scaleSlider:SetPoint("TOPLEFT", LX, -y)
    self.scaleSlider:SetValue(ns.db.scale or 1)
    self.scaleSlider:Show(); y = y + 24

    return y
end

-- ----------------------------------------------------------------- refresh --
function UI:Refresh()
    local f = self.frame
    if not f then return end
    if ns.db.tab == "info" then ns.db.tab = "coverage" end  -- Info folded into Coverage

    local key = ns.db.dungeon
    local detected = self:DetectDungeon()
    if ns.db.auto and detected then key = detected; ns.db.dungeon = key end
    local dungeon = ns.Dungeons.list[key] or ns.Dungeons.list[ns.Dungeons.order[1]]

    self.autoCheck:SetChecked(ns.db.auto)
    if not ns.db.auto then
        self.autoLabel:SetText("Auto  " .. GREY .. "(off \226\128\148 manual: " .. dungeon.name .. ")" .. R)
    elseif detected then
        self.autoLabel:SetText("Auto  " .. GREY .. "(detected: " .. ns.Dungeons.list[detected].name .. ")" .. R)
    else
        self.autoLabel:SetText("Auto  " .. GREY .. "(no dungeon detected \226\128\148 pick one)" .. R)
    end
    self.dname:SetText(WHITE .. dungeon.name .. R)

    self.roster = ns.Roster.Read()
    self.cov = C.Compute(self.roster, key)
    self.dungeon = dungeon
    self.dungeonKey = key

    self:HideAllTabs()
    self:UpdateTabs()

    local tab = ns.db.tab or "coverage"
    local bottom
    if tab == "applicants" then
        bottom = self:RenderApplicants()
    else
        bottom = self:RenderCoverage()
    end

    local contentH = bottom + 6
    self.child:SetHeight(math.max(contentH, 1))
    local screenH = (UIParent and UIParent:GetHeight()) or 768
    local maxVis = math.max(MAX_VIS, screenH * 0.9 - CONTENT_TOP - PAD)
    local vis = math.min(contentH, maxVis)
    self.scroll:SetHeight(vis)
    self.scroll.contentHeight = contentH
    f:SetHeight(CONTENT_TOP + vis + PAD)

    local maxScroll = math.max(0, contentH - vis)
    if self.scroll:GetVerticalScroll() > maxScroll then self.scroll:SetVerticalScroll(maxScroll) end
    self:UpdateScrollHint()

    if self.updatedText then
        self.updatedText:SetText(GREY .. (date and date("%H:%M:%S") or "") .. R)
    end
end
