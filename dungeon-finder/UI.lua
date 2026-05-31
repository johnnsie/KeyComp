local addonName, ns = ...

-- =========================================================================
-- UI: movable, scrollable, tabbed panel (scaffold mirrors KeyComp's).
--   Queue    - the auto-mode console: role, key, target dungeons, big Start/Stop,
--              and a live status block (counters + next-up + activity log)
--   Listings - the current ranked Mythic+ listings, each with a one-click Apply
--   Settings - apply behaviour knobs, panel scale, blacklist, caveats
-- =========================================================================

local UI = {}
ns.UI = UI

local PAD = 14
local WIDTH = 440
local CONTENT_TOP = 92
local MAX_VIS = 420
local LX = 6

local GREEN  = "|cff40ff40"
local YELLOW = "|cffffd200"
local RED    = "|cffff5555"
local GREY   = "|cff999999"
local WHITE  = "|cffffffff"
local BLUE   = "|cff66ccff"
local ORANGE = "|cffffa020"
local R      = "|r"

local ROLE_DEF = {
    { key = "TANK",    label = "Tank", rgb = { 0.32, 0.58, 0.96 } },
    { key = "HEALER",  label = "Heal", rgb = { 0.40, 0.80, 0.45 } },
    { key = "DAMAGER", label = "DPS",  rgb = { 0.90, 0.42, 0.40 } },
}
local ROLE_DISPLAY = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

local function hideTip() GameTooltip:Hide() end

local function fmtAge(s)
    s = s or 0
    if s < 60 then return s .. "s" end
    if s < 3600 then return math.floor(s / 60) .. "m" end
    return math.floor(s / 3600) .. "h"
end

-- ------------------------------------------------------------ control kit --
-- a "- value +" stepper bound to a db field; reads/writes ns.db live.
function UI:MakeStepper(field, minv, maxv, step, label, onChange)
    local child = self.child
    local c = {}
    c.fs  = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.fs:SetJustifyH("LEFT")
    c.dec = CreateFrame("Button", nil, child, "UIPanelButtonTemplate"); c.dec:SetSize(22, 18); c.dec:SetText("-")
    c.val = child:CreateFontString(nil, "OVERLAY", "GameFontNormal"); c.val:SetJustifyH("CENTER"); c.val:SetWidth(34)
    c.inc = CreateFrame("Button", nil, child, "UIPanelButtonTemplate"); c.inc:SetSize(22, 18); c.inc:SetText("+")
    local function get() return ns.db[field] or minv end
    local function set(v)
        if v < minv then v = minv elseif v > maxv then v = maxv end
        ns.db[field] = v
        if onChange then onChange(v) end
        UI:Refresh()
    end
    c.dec:SetScript("OnClick", function() set(get() - step) end)
    c.inc:SetScript("OnClick", function() set(get() + step) end)
    c.Hide = function() c.fs:Hide(); c.dec:Hide(); c.val:Hide(); c.inc:Hide() end
    c.Show = function(_, x, y, width)
        width = width or 250
        c.fs:ClearAllPoints();  c.fs:SetPoint("TOPLEFT", x, -y);          c.fs:SetText(label)
        c.inc:ClearAllPoints(); c.inc:SetPoint("TOPLEFT", x + width, -y + 1)
        c.val:ClearAllPoints(); c.val:SetPoint("RIGHT", c.inc, "LEFT", -3, 0); c.val:SetText(tostring(get()))
        c.dec:ClearAllPoints(); c.dec:SetPoint("RIGHT", c.val, "LEFT", -3, 0)
        c.fs:Show(); c.dec:Show(); c.val:Show(); c.inc:Show()
    end
    return c
end

-- a labelled checkbox bound to a db field.
function UI:MakeCheck(field, label, onChange)
    local child = self.child
    local cb = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local fsL = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fsL:SetJustifyH("LEFT")
    cb:SetScript("OnClick", function(b)
        ns.db[field] = b:GetChecked() and true or false
        if onChange then onChange(ns.db[field]) end
        UI:Refresh()
    end)
    local o = {}
    o.Hide = function() cb:Hide(); fsL:Hide() end
    o.Show = function(_, x, y)
        cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", x, -y); cb:SetChecked(ns.db[field] and true or false)
        fsL:ClearAllPoints(); fsL:SetPoint("LEFT", cb, "RIGHT", 2, 0); fsL:SetText(label)
        cb:Show(); fsL:Show()
    end
    return o
end

-- a flat colored button (used for role pills and the big Start/Stop).
local function makeFlatButton(parent, w, h, font)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.12)
    b.text = b:CreateFontString(nil, "OVERLAY", font or "GameFontNormal"); b.text:SetAllPoints(); b.text:SetJustifyH("CENTER")
    return b
end

-- ---------------------------------------------------------------- build ----
function UI:Init()
    if self.frame then return end

    local f = CreateFrame("Frame", "KeyQueueFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(WIDTH, 300)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
    f:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:SetScale((ns.db and ns.db.scale) or 1)

    local function stopMoving()
        if not f.isMoving then return end
        f:SetScript("OnUpdate", nil); f:StopMovingOrSizing(); f.isMoving = false; UI:SavePosition()
    end
    f:SetScript("OnMouseDown", function(self2, button)
        if button ~= "LeftButton" or self2.isMoving then return end
        self2:StartMoving(); self2.isMoving = true
        self2:SetScript("OnUpdate", function() if not IsMouseButtonDown("LeftButton") then stopMoving() end end)
    end)
    f:SetScript("OnMouseUp", function() stopMoving() end)
    f:SetScript("OnHide", function() stopMoving() end)
    f:Hide()
    UI:RestorePosition()

    -- green flash overlay for an incoming invite
    self.flash = f:CreateTexture(nil, "OVERLAY")
    self.flash:SetAllPoints()
    self.flash:SetColorTexture(0.20, 0.85, 0.30, 0.0)
    self.flash:SetBlendMode("ADD")
    self.flash:Hide()

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() UI:Hide() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText(WHITE .. "KeyQueue" .. R)

    self.statePill = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.statePill:SetPoint("LEFT", title, "RIGHT", 10, 0)

    self.updatedText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.updatedText:SetPoint("TOPRIGHT", -30, -PAD - 2)

    -- tab bar
    local function makeTab(key, label, x)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(100, 24)
        b:SetPoint("TOPLEFT", x, -42)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetAllPoints(); b.text:SetText(label)
        b.underline = b:CreateTexture(nil, "OVERLAY"); b.underline:SetColorTexture(0.95, 0.82, 0.20, 1)
        b.underline:SetHeight(2); b.underline:SetPoint("BOTTOMLEFT", 6, -1); b.underline:SetPoint("BOTTOMRIGHT", -6, -1)
        b:SetScript("OnClick", function()
            ns.db.tab = key
            if UI.scroll then UI.scroll:SetVerticalScroll(0) end
            UI:Refresh()
        end)
        b.key = key
        return b
    end
    self.tabs = {
        makeTab("queue", "Queue", PAD),
        makeTab("listings", "Listings", PAD + 104),
        makeTab("settings", "Settings", PAD + 208),
    }
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(0.3, 0.3, 0.35, 0.8); div:SetHeight(1)
    div:SetPoint("TOPLEFT", PAD, -68); div:SetPoint("TOPRIGHT", -PAD, -68)

    -- always-visible Start/Stop in the header: parented to the frame (not the
    -- scrolling content), so it's on every tab and can never be scrolled away.
    self.headerStart = makeFlatButton(f, 104, 22)
    self.headerStart:SetPoint("TOPRIGHT", -8, -39)
    self.headerStart:SetScript("OnClick", function() ns.Queue:Toggle() end)

    -- scroll area
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
        s:SetVerticalScroll(nw); UI:UpdateScrollHint()
    end)
    self.scroll = scroll
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(childW, 100)
    scroll:SetScrollChild(child)
    self.child = child

    self.scrollHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.scrollHint:SetPoint("BOTTOMRIGHT", -PAD, PAD - 4)
    self.scrollHint:SetText(GREY .. "scroll" .. R); self.scrollHint:Hide()

    local FSW = childW - 2 * LX
    local function fs(tmpl)
        local s = child:CreateFontString(nil, "OVERLAY", tmpl or "GameFontHighlightSmall")
        s:SetJustifyH("LEFT"); s:SetWidth(FSW); s:SetWordWrap(true)
        return s
    end
    self.fs = fs

    -- ---------- Queue tab widgets ----------
    self.q_inviteBanner = fs("GameFontNormalLarge")
    self.q_roleLabel = fs("GameFontNormalSmall")
    self.roleBtns = {}
    for i, def in ipairs(ROLE_DEF) do
        local b = makeFlatButton(child, 56, 22)
        b.def = def
        b:SetScript("OnClick", function()
            ns.db.role = def.key; UI:Refresh()
        end)
        self.roleBtns[i] = b
    end

    self.stKey = self:MakeStepper("targetKey", 2, 40, 1, "Key level  +", function(v)
        if (ns.db.keyMax or v) < v then ns.db.keyMax = v end
    end)
    self.stKeyMax = self:MakeStepper("keyMax", 2, 40, 1, "up to  +", function(v)
        if v < (ns.db.targetKey or v) then ns.db.keyMax = ns.db.targetKey end
    end)

    self.q_targetsLabel = fs("GameFontNormalSmall")
    self.autoTargetsBtn = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    self.autoTargetsBtn:SetSize(120, 18); self.autoTargetsBtn:SetText("Auto: needed only")
    self.autoTargetsBtn:SetScript("OnClick", function()
        ns.db.autoTargets = true; ns.db.dungeons = nil; UI:Refresh()
    end)

    self.chips = {}
    for i = 1, #ns.Dungeons.order do
        local key = ns.Dungeons.order[i]
        local chip = makeFlatButton(child, 96, 26, "GameFontHighlightSmall")
        chip.dungeonKey = key
        chip:SetScript("OnClick", function() UI:ToggleDungeon(key) end)
        chip:SetScript("OnEnter", function(b) UI:ChipTip(b, key) end)
        chip:SetScript("OnLeave", hideTip)
        self.chips[i] = chip
    end

    self.chkAuto = self:MakeCheck("autoApply", "Try timer auto-apply  " .. GREY .. "(usually blocked by Blizzard)" .. R)
    self.stPending = self:MakeStepper("maxPending", 1, 10, 1, "Keep applications pending")

    -- application note: text whispered to the leader on apply (retail PGF has no
    -- native applicant-note field, so a whisper is the only way to attach one).
    self.noteLabel = fs("GameFontNormalSmall")
    self.noteEdit = CreateFrame("EditBox", nil, child, "InputBoxTemplate")
    self.noteEdit:SetAutoFocus(false)
    self.noteEdit:SetHeight(20)
    self.noteEdit:SetMaxLetters(255)
    self.noteEdit:SetScript("OnTextChanged", function(eb) ns.db.note = eb:GetText() end)
    self.noteEdit:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    self.noteEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    self.chkWhisper = self:MakeCheck("whisperNote", "Whisper note to leader on apply")

    self.startBtn = makeFlatButton(child, 240, 30, "GameFontNormalLarge")
    self.startBtn:SetScript("OnClick", function() ns.Queue:Toggle() end)

    -- one-tap apply (a real click is a hardware event, so the protected apply works)
    self.applyNextBtn = makeFlatButton(child, 240, 26, "GameFontNormal")
    self.applyNextBtn:SetScript("OnClick", function() ns.Queue:ApplyNext() end)
    self.applyHint = fs("GameFontDisableSmall")

    self.q_state = fs("GameFontNormal")
    self.q_counts = fs()
    self.q_next = fs()
    self.q_logHeader = fs("GameFontNormalSmall")
    self.logLines = {}
    for i = 1, 8 do self.logLines[i] = fs("GameFontDisableSmall") end

    -- ---------- Listings tab widgets ----------
    self.l_recap = fs()
    self.l_head = {}
    for _, h in ipairs({ { k = "grp", t = "Group" }, { k = "leader", t = "Leader (score)" }, { k = "slots", t = "T H D" }, { k = "age", t = "Age" } }) do
        local s = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); s:SetText(h.t)
        self.l_head[h.k] = s
    end
    self.l_empty = fs()
    self.resultRows = {}
    for i = 1, 18 do
        local row = CreateFrame("Button", nil, child)
        row:SetSize(childW - 12, 18)
        row.hl = row:CreateTexture(nil, "BACKGROUND"); row.hl:SetAllPoints(); row.hl:SetColorTexture(0.25, 0.55, 0.95, 0.12); row.hl:Hide()
        local function col(x, w, justify)
            local s = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            s:SetPoint("LEFT", x, 0); s:SetWidth(w); s:SetJustifyH(justify or "LEFT"); s:SetWordWrap(false)
            return s
        end
        row.grp    = col(0, 64)
        row.leader = col(66, 150)
        row.slots  = col(220, 60)
        row.age    = col(282, 34, "RIGHT")
        row.apply  = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.apply:SetSize(62, 18); row.apply:SetPoint("RIGHT", 0, 0); row.apply:SetNormalFontObject(GameFontNormalSmall)
        row:SetScript("OnLeave", hideTip)
        self.resultRows[i] = row
    end

    -- ---------- Settings tab widgets ----------
    self.stMaxApps  = self:MakeStepper("maxApps", 5, 500, 5, "Max applies / session")
    self.stMinScore = self:MakeStepper("minLeaderScore", 0, 4000, 100, "Min leader score")
    self.stBlack    = self:MakeStepper("blacklistMins", 1, 60, 1, "Blacklist a decliner (min)")
    self.chkGated   = self:MakeCheck("skipGated", "Skip listings I'm rating-gated from")
    self.chkUnknown = self:MakeCheck("includeUnknownKey", "Apply to listings with no readable +key")
    self.chkMinimap = self:MakeCheck("minimapHide", "Hide minimap button", function() UI:UpdateMinimap() end)
    self.chkOwnSearch = self:MakeCheck("useOwnSearch", "Drive my own search  " .. GREY .. "(else read your Blizzard PGF)" .. R)
    self.clearBlBtn = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    self.clearBlBtn:SetSize(140, 20); self.clearBlBtn:SetText("Clear blacklist")
    self.clearBlBtn:SetScript("OnClick", function()
        wipe(ns.Queue.blacklist); ns.Queue:Note("Blacklist cleared"); UI:Refresh()
    end)
    self.s_scaleLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); self.s_scaleLabel:SetJustifyH("LEFT")
    local slider = CreateFrame("Slider", nil, child)
    slider:SetOrientation("HORIZONTAL"); slider:SetSize(200, 16)
    slider:SetMinMaxValues(0.7, 1.6); slider:SetValueStep(0.05)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture(); if thumb then thumb:SetSize(14, 18) end
    local track = slider:CreateTexture(nil, "BACKGROUND"); track:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    track:SetHeight(4); track:SetPoint("LEFT", 2, 0); track:SetPoint("RIGHT", -2, 0)
    slider:SetScript("OnValueChanged", function(self2, val)
        val = math.floor(val * 20 + 0.5) / 20; self2.pending = val
        if UI.s_scaleLabel then UI.s_scaleLabel:SetText("Panel scale: " .. math.floor(val * 100 + 0.5) .. "%") end
    end)
    slider:SetScript("OnMouseUp", function(self2)
        local val = self2.pending or self2:GetValue(); ns.db.scale = val
        if UI.frame then UI.frame:SetScale(val) end
    end)
    self.s_scaleSlider = slider
    self.s_help = fs("GameFontDisableSmall")

    self:InitMinimap()
    self:UpdateTabs()
end

-- --------------------------------------------------------------- generic --
function UI:SavePosition()
    local f = self.frame; if not f then return end
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    ns.db.point = { left = left, top = top }
end

function UI:RestorePosition()
    local f = self.frame; if not f then return end
    f:ClearAllPoints()
    local p = ns.db and ns.db.point
    if p and p.left and p.top then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

function UI:Show() if not self.frame then self:Init() end; self.frame:Show(); ns.db.shown = true; self:Refresh() end
function UI:Hide() if self.frame then self.frame:Hide() end; ns.db.shown = false end
function UI:Toggle() if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end end

function UI:UpdateTabs()
    if not self.tabs then return end
    local active = ns.db and ns.db.tab or "queue"
    for _, b in ipairs(self.tabs) do
        if b.key == active then b.text:SetTextColor(1, 1, 1); b.underline:Show()
        else b.text:SetTextColor(0.6, 0.6, 0.6); b.underline:Hide() end
    end
end

function UI:UpdateScrollHint()
    local s = self.scroll; if not s or not self.scrollHint then return end
    local range = math.max(0, (s.contentHeight or 0) - s:GetHeight())
    if range > 1 and s:GetVerticalScroll() < range - 1 then self.scrollHint:Show() else self.scrollHint:Hide() end
end

function UI:FlashInvite()
    local t = self.flash; if not t or not C_Timer then return end
    t:Show()
    local n = 0
    local function pulse()
        n = n + 1
        t:SetAlpha((n % 2 == 0) and 0.0 or 0.45)
        if n < 10 then C_Timer.After(0.35, pulse) else t:SetAlpha(0); t:Hide() end
    end
    pulse()
end

-- -------------------------------------------------------- minimap button ---
-- Self-contained (no LibDBIcon dependency). Left-click toggles the queue,
-- right-click toggles the panel, drag moves it around the minimap ring.
function UI:InitMinimap()
    if self.minimapBtn or not Minimap then return end
    local mb = CreateFrame("Button", "KeyQueueMinimapButton", Minimap)
    self.minimapBtn = mb
    mb:SetSize(31, 31)
    mb:SetFrameStrata("MEDIUM")
    mb:SetFrameLevel(8)
    mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mb:RegisterForDrag("LeftButton")

    local icon = mb:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Relics_Hourglass")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim the square icon border
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", 0, 1)
    mb.icon = icon

    local ring = mb:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")

    local dot = mb:CreateTexture(nil, "OVERLAY", nil, 1)   -- state indicator
    dot:SetTexture("Interface\\Buttons\\WHITE8x8")
    dot:SetSize(7, 7)
    dot:SetPoint("CENTER", mb, "TOPRIGHT", -9, -9)
    dot:Hide()
    mb.dot = dot

    local function updatePos()
        local angle = math.rad(ns.db.minimapAngle or 214)
        local r = (Minimap:GetWidth() / 2) + 6
        mb:ClearAllPoints()
        mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
    end
    self.UpdateMinimapPos = updatePos

    mb:SetScript("OnDragStart", function(self2)
        self2:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local px, py = GetCursorPosition()
            px, py = px / scale, py / scale
            local atan2 = math.atan2 or math.atan   -- 5.1 has atan2; later Lua uses atan(y,x)
            ns.db.minimapAngle = math.deg(atan2(py - my, px - mx))
            updatePos()
        end)
    end)
    mb:SetScript("OnDragStop", function(self2) self2:SetScript("OnUpdate", nil) end)

    mb:SetScript("OnClick", function(_, button)
        if button == "RightButton" then UI:Toggle() else ns.Queue:Toggle() end
        UI:UpdateMinimap()
    end)
    mb:SetScript("OnEnter", function(self2)
        GameTooltip:SetOwner(self2, "ANCHOR_LEFT")
        GameTooltip:SetText("KeyQueue", 1, 1, 1)
        GameTooltip:AddLine(ns.Queue.invitedBy and (GREEN .. "INVITED -- accept or decline" .. R)
            or (ns.Queue.active and (GREEN .. "Queueing" .. R) or (GREY .. "Idle" .. R)))
        GameTooltip:AddLine("Left-click: start / stop queue", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: show / hide panel", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    mb:SetScript("OnLeave", hideTip)

    updatePos()
    self:UpdateMinimap()
end

function UI:UpdateMinimap()
    local mb = self.minimapBtn
    if not mb then return end
    if ns.db and ns.db.minimapHide then mb:Hide() else mb:Show() end
    local active = ns.Queue.active
    if mb.icon then mb.icon:SetVertexColor(active and 0.55 or 1, 1, active and 0.55 or 1) end
    if mb.dot then
        if ns.Queue.invitedBy then mb.dot:SetColorTexture(0.30, 0.90, 0.30, 1); mb.dot:Show()
        elseif active then mb.dot:SetColorTexture(0.30, 0.85, 0.35, 1); mb.dot:Show()
        else mb.dot:Hide() end
    end
end

-- ------------------------------------------------------------- dungeons ----
function UI:EnsureManualSet()
    if ns.db.dungeons then return end
    local cur = ns.Filter:Criteria().dungeons
    local set = {}
    for _, key in ipairs(ns.Dungeons.order) do
        set[key] = (cur == nil) or (cur[key] and true or false)
    end
    ns.db.dungeons = set
end

function UI:ToggleDungeon(key)
    self:EnsureManualSet()
    ns.db.autoTargets = false
    ns.db.dungeons[key] = not ns.db.dungeons[key]
    self:Refresh()
end

function UI:ChipTip(owner, key)
    local d = ns.Dungeons.list[key]
    local best = ns.Progress:BestLevel(key)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(d.name, 1, 1, 1)
    if best > 0 then GameTooltip:AddLine("Season best: +" .. best, 0.7, 0.85, 0.7)
    else GameTooltip:AddLine("No completed run this season", 0.85, 0.7, 0.5) end
    local tgt = ns.db.targetKey or 19
    if best >= tgt then GameTooltip:AddLine(("Already done at +%d -- not a target"):format(tgt), 0.6, 0.6, 0.6, true)
    else GameTooltip:AddLine(("Still want a +%d here"):format(tgt), 0.5, 0.85, 0.5, true) end
    GameTooltip:AddLine("Click to include/exclude (switches to manual targets)", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

-- ------------------------------------------------------------- hide all ----
function UI:HideAll()
    self.q_inviteBanner:Hide(); self.q_roleLabel:Hide()
    for _, b in ipairs(self.roleBtns) do b:Hide() end
    self.stKey:Hide(); self.stKeyMax:Hide()
    self.q_targetsLabel:Hide(); self.autoTargetsBtn:Hide()
    for _, c in ipairs(self.chips) do c:Hide() end
    self.chkAuto:Hide(); self.stPending:Hide()
    self.noteLabel:Hide(); self.noteEdit:Hide(); self.chkWhisper:Hide()
    self.startBtn:Hide(); self.applyNextBtn:Hide(); self.applyHint:Hide()
    self.q_state:Hide(); self.q_counts:Hide(); self.q_next:Hide(); self.q_logHeader:Hide()
    for _, l in ipairs(self.logLines) do l:Hide() end

    self.l_recap:Hide(); self.l_empty:Hide()
    for _, h in pairs(self.l_head) do h:Hide() end
    for _, row in ipairs(self.resultRows) do row:Hide(); row.apply:Hide() end

    self.stMaxApps:Hide(); self.stMinScore:Hide(); self.stBlack:Hide()
    self.chkGated:Hide(); self.chkUnknown:Hide(); self.chkMinimap:Hide()
    self.chkOwnSearch:Hide(); self.clearBlBtn:Hide()
    self.s_scaleLabel:Hide(); self.s_scaleSlider:Hide(); self.s_help:Hide()
end

-- --------------------------------------------------------------- helpers ---
local REASON_HELP = {
    ["no-slot"]      = "no open slot for your role",
    ["key"]          = "key not in your range",
    ["unknown-key"]  = "no readable +key (Settings toggle)",
    ["dungeon-done"] = "dungeon already done",
    ["gated"]        = "rating req > yours",
    ["leader-score"] = "leader below your min score",
    ["blacklist"]    = "recently declined you",
}
local function friendlyReasons(reasons)
    local order = {}
    for k, v in pairs(reasons or {}) do order[#order + 1] = { k = k, v = v } end
    if #order == 0 then return "" end
    table.sort(order, function(a, b) return a.v > b.v end)
    local t = {}
    for i = 1, math.min(3, #order) do
        t[#t + 1] = order[i].v .. " " .. (REASON_HELP[order[i].k] or order[i].k)
    end
    return table.concat(t, ", ")
end

function UI:CurrentMatches()
    local results = ns.Search.lastResults or {}
    local c = ns.Filter:Criteria()
    local ctx = ns.Queue:Ctx()
    local matched, reasons = ns.Filter:Evaluate(results, c, ctx)
    return matched, c, reasons, #results
end

local function leaderCell(r)
    local nm = r.leaderName or "?"
    local sc = (r.leaderScore and r.leaderScore > 0) and ("  " .. GREY .. r.leaderScore .. R) or ""
    return nm .. sc
end

-- "T H D" with the open slot for each role lit; your role emphasised.
local function slotsCell(r, myRole)
    local function pip(letter, count, cap, role)
        local open = count < cap
        local col = open and GREEN or GREY
        if role == myRole and open then col = YELLOW end
        return col .. letter .. R
    end
    return pip("T", r.tank, 1, "TANK") .. " " .. pip("H", r.heal, 1, "HEALER") .. " " .. pip("D", r.dps, 3, "DAMAGER")
end

-- ---------------------------------------------------------- Queue render ---
function UI:RenderQueue()
    local db = ns.db
    local q = ns.Queue
    local y = 4

    -- invite banner
    if q.invitedBy then
        self.q_inviteBanner:ClearAllPoints(); self.q_inviteBanner:SetPoint("TOPLEFT", LX, -y)
        self.q_inviteBanner:SetText(GREEN .. "INVITED by " .. q.invitedBy .. " -- accept it, or decline to keep searching" .. R)
        self.q_inviteBanner:Show(); y = y + 26
    end

    -- role row
    self.q_roleLabel:ClearAllPoints(); self.q_roleLabel:SetPoint("TOPLEFT", LX, -y)
    self.q_roleLabel:SetText("Apply as"); self.q_roleLabel:Show()
    local myRole = ns.Filter:Role()
    local rx = LX + 64
    for _, b in ipairs(self.roleBtns) do
        local on = (b.def.key == myRole)
        local c = b.def.rgb
        b.bg:SetColorTexture(c[1], c[2], c[3], on and 0.85 or 0.18)
        b.text:SetText(b.def.label)
        b.text:SetTextColor(1, 1, 1, on and 1 or 0.7)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", rx, -y + 2)
        b:Show(); rx = rx + 60
    end
    y = y + 28

    -- key range
    self.stKey:Show(LX, y, 150); y = y + 22
    self.stKeyMax:Show(LX, y, 150); y = y + 24

    -- targets summary + auto button
    local c = ns.Filter:Criteria()
    local nTargets = 0
    if c.dungeons then for _ in pairs(c.dungeons) do nTargets = nTargets + 1 end else nTargets = #ns.Dungeons.order end
    local mode = (db.autoTargets ~= false) and (BLUE .. "auto" .. R) or (ORANGE .. "manual" .. R)
    local prog = ns.Progress:Loaded() and "" or (GREY .. "  (progress not loaded -- using all)" .. R)
    self.q_targetsLabel:ClearAllPoints(); self.q_targetsLabel:SetPoint("TOPLEFT", LX, -y)
    self.q_targetsLabel:SetText(WHITE .. "Target dungeons" .. R .. "  " .. mode ..
        GREY .. "  " .. nTargets .. " selected" .. R .. prog)
    self.q_targetsLabel:Show()
    self.autoTargetsBtn:ClearAllPoints(); self.autoTargetsBtn:SetPoint("TOPLEFT", LX + 280, -y - 1)
    self.autoTargetsBtn:Show()
    y = y + 20

    -- dungeon chips (4 per row)
    local tgt = db.targetKey or 19
    local cols, chipW, chipH, gap = 4, 96, 26, 4
    for i, key in ipairs(ns.Dungeons.order) do
        local chip = self.chips[i]
        local d = ns.Dungeons.list[key]
        local best = ns.Progress:BestLevel(key)
        local isTarget = (c.dungeons == nil) or (c.dungeons[key] and true or false)
        local label = d.abbr
        if best >= tgt then label = d.abbr .. " " .. GREEN .. "\226\156\147" .. R     -- done at target
        elseif best > 0 then label = d.abbr .. " " .. GREY .. best .. R end           -- best so far
        chip.text:SetText(label)
        chip.text:SetTextColor(1, 1, 1, isTarget and 1 or 0.5)
        if isTarget then chip.bg:SetColorTexture(0.22, 0.42, 0.30, 0.85)
        else chip.bg:SetColorTexture(0.18, 0.18, 0.20, 0.6) end
        local rowi = math.floor((i - 1) / cols)
        local coli = (i - 1) % cols
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", LX + coli * (chipW + gap), -(y + rowi * (chipH + gap)))
        chip:Show()
    end
    y = y + 2 * (chipH + gap) + 6

    -- auto-apply + pending
    self.chkAuto:Show(LX, y); y = y + 24
    self.stPending:Show(LX, y, 250); y = y + 26

    -- application note (whispered to the leader on apply, if enabled)
    self.noteLabel:ClearAllPoints(); self.noteLabel:SetPoint("TOPLEFT", LX, -y)
    self.noteLabel:SetText("Note to leader  " .. GREY .. "(whispered on apply if ticked below)" .. R)
    self.noteLabel:Show(); y = y + 16
    self.noteEdit:ClearAllPoints(); self.noteEdit:SetPoint("TOPLEFT", LX + 6, -y)
    self.noteEdit:SetWidth(self.childW - 2 * LX - 12)
    if not self.noteEdit:HasFocus() and self.noteEdit:GetText() ~= (ns.db.note or "") then
        self.noteEdit:SetText(ns.db.note or "")
    end
    self.noteEdit:Show(); y = y + 26
    self.chkWhisper:Show(LX, y); y = y + 26

    -- big Start/Stop (Start = begin continuously finding + ranking + tracking invites)
    local active = q.active
    self.startBtn.bg:SetColorTexture(active and 0.70 or 0.18, active and 0.20 or 0.55, active and 0.20 or 0.28, 0.95)
    self.startBtn.text:SetText(active and "Stop finding" or ("Start finding (+" .. (db.targetKey or 19) .. ")"))
    self.startBtn.text:SetTextColor(1, 1, 1)
    self.startBtn:ClearAllPoints(); self.startBtn:SetPoint("TOPLEFT", LX, -y); y = y + 34

    -- one-tap apply: each click/keypress applies to the top match (hardware event)
    self.applyNextBtn.bg:SetColorTexture(0.20, 0.42, 0.64, 0.95)
    self.applyNextBtn.text:SetText("Apply to next best  \226\150\182")
    self.applyNextBtn.text:SetTextColor(1, 1, 1)
    self.applyNextBtn:ClearAllPoints(); self.applyNextBtn:SetPoint("TOPLEFT", LX, -y); y = y + 30
    self.applyHint:ClearAllPoints(); self.applyHint:SetPoint("TOPLEFT", LX, -y)
    self.applyHint:SetText(GREY .. "Bind a key: Esc > Key Bindings > KeyQueue, then tap it to fire each apply." .. R)
    self.applyHint:Show(); y = y + self.applyHint:GetStringHeight() + 8

    -- status block
    local stateStr
    if q.invitedBy then stateStr = GREEN .. "INVITED -- accept, or decline to keep searching" .. R
    elseif active then
        if C_LFGList and C_LFGList.HasActiveEntry and C_LFGList.HasActiveEntry() then
            stateStr = YELLOW .. "Paused (you're listing your own group)" .. R
        else stateStr = GREEN .. "Queueing\226\128\166" .. R end
    else stateStr = GREY .. "Idle" .. R end
    self.q_state:ClearAllPoints(); self.q_state:SetPoint("TOPLEFT", LX, -y)
    self.q_state:SetText(WHITE .. "Status: " .. R .. stateStr); self.q_state:Show(); y = y + 20

    local s = q.stats
    self.q_counts:ClearAllPoints(); self.q_counts:SetPoint("TOPLEFT", LX, -y)
    self.q_counts:SetText(GREY .. "searched " .. R .. s.searched ..
        GREY .. "  matched " .. R .. s.matched ..
        GREY .. "  applied " .. R .. GREEN .. s.applied .. R ..
        GREY .. "  pending " .. R .. q:Pending() ..
        GREY .. "  declined " .. R .. RED .. s.declined .. R)
    self.q_counts:Show(); y = y + 18

    local matched, _, reasons, nres = self:CurrentMatches()
    self.q_next:ClearAllPoints(); self.q_next:SetPoint("TOPLEFT", LX, -y)
    if q.invitedBy then
        self.q_next:SetText(GREEN .. "Invite pending" .. R ..
            GREY .. " -- accept it, or decline in-game to resume searching" .. R)
    elseif matched[1] then
        -- show the best match we'd actually APPLY to (one-tap skips "+?") so a key-less
        -- group never misleads as "tap Apply".
        local pick
        for _, rr in ipairs(matched) do
            if ns.Queue:Eligible(rr, c) then pick = rr; break end
        end
        if pick then
            self.q_next:SetText(GREEN .. "Next up: " .. R .. "+" .. (pick.keyLevel or "?") .. " " ..
                (pick.abbr or "?") .. "  " .. (pick.leaderName or "?") .. GREY .. "  -- tap Apply" .. R)
        else
            self.q_next:SetText(YELLOW .. #matched .. " group(s) found, none with a readable +" ..
                (c.minKey or 19) .. R .. GREY .. " -- type +" .. (c.minKey or 19) ..
                " in Blizzard's Group Finder so titles show the key" .. R)
        end
    elseif (nres or 0) > 0 then
        self.q_next:SetText(YELLOW .. "0 / " .. nres .. " listings match" .. R .. GREY .. "  -- " .. friendlyReasons(reasons) .. R)
    else
        self.q_next:SetText(GREY .. "No listings -- open Blizzard's Group Finder and search (+" ..
            (db.targetKey or 19) .. " / your dungeons). KeyQueue ranks what it shows." .. R)
    end
    self.q_next:Show(); y = y + math.max(22, self.q_next:GetStringHeight() + 6)

    -- recent log
    self.q_logHeader:ClearAllPoints(); self.q_logHeader:SetPoint("TOPLEFT", LX, -y)
    self.q_logHeader:SetText(WHITE .. "Recent activity" .. R); self.q_logHeader:Show(); y = y + 16
    for i = 1, #self.logLines do
        local line = self.logLines[i]
        local entry = q.log[i]
        if entry then
            line:ClearAllPoints(); line:SetPoint("TOPLEFT", LX, -y)
            line:SetText(GREY .. (entry.ts or "") .. R .. "  " .. (entry.msg or ""))
            line:Show(); y = y + 14
        else line:Hide() end
    end

    return y
end

-- -------------------------------------------------------- Listings render --
function UI:RenderListings()
    local y = 4
    local matched, c, reasons, nres = self:CurrentMatches()
    local myRole = c.role

    local keyStr = "+" .. c.minKey .. (c.maxKey ~= c.minKey and ("-" .. c.maxKey) or "")
    self.l_recap:ClearAllPoints(); self.l_recap:SetPoint("TOPLEFT", LX, -y)
    self.l_recap:SetText(GREY .. "Showing " .. R .. WHITE .. ROLE_DISPLAY[myRole] .. R .. GREY .. " slots in " .. R ..
        keyStr .. GREY .. " keys you still need  " .. R ..
        (ns.Search.lastResults and (GREY .. "(" .. #ns.Search.lastResults .. " M+ listings seen)" .. R) or ""))
    self.l_recap:Show(); y = y + 20

    if #matched == 0 then
        self.l_empty:ClearAllPoints(); self.l_empty:SetPoint("TOPLEFT", LX, -y)
        local msg
        if (nres or 0) > 0 then
            msg = "0 of " .. nres .. " listings match -- " .. friendlyReasons(reasons) ..
                ".  Loosen the key range or dungeons, or check Settings."
        elseif C_LFGList and C_LFGList.GetSearchResults then
            msg = "No listings. Open Blizzard's Group Finder and search (filter to your key/dungeons) -- KeyQueue ranks what it shows."
        else
            msg = "Group Finder API unavailable."
        end
        self.l_empty:SetText(GREY .. msg .. R); self.l_empty:Show()
        return y + 18
    end

    -- headers
    self.l_head.grp:ClearAllPoints();    self.l_head.grp:SetPoint("TOPLEFT", LX, -y)
    self.l_head.leader:ClearAllPoints(); self.l_head.leader:SetPoint("TOPLEFT", LX + 66, -y)
    self.l_head.slots:ClearAllPoints();  self.l_head.slots:SetPoint("TOPLEFT", LX + 220, -y)
    self.l_head.age:ClearAllPoints();    self.l_head.age:SetPoint("TOPLEFT", LX + 282, -y)
    for _, h in pairs(self.l_head) do h:Show() end
    y = y + 14

    local n = math.min(#matched, #self.resultRows)
    for i = 1, n do
        local r = matched[i]
        local row = self.resultRows[i]
        row.grp:SetText(WHITE .. (r.abbr or "?") .. R .. " +" .. (r.keyLevel or "?"))
        row.leader:SetText(leaderCell(r))
        row.slots:SetText(slotsCell(r, myRole))
        row.age:SetText(GREY .. fmtAge(r.ageSeconds) .. R)

        local status = ns.Queue:StatusOf(r.resultID)
        local invited = status == "invited" or status == "inviteaccepted"
        local pending = status == "applied"
        if row.hl then if invited then row.hl:SetColorTexture(0.20, 0.70, 0.25, 0.20); row.hl:Show()
            elseif pending then row.hl:SetColorTexture(0.25, 0.55, 0.95, 0.12); row.hl:Show()
            else row.hl:Hide() end end

        row.apply:SetScript("OnClick", function() ns.Queue:ApplyManual(r) end)
        local canApply = ns.Queue:Eligible(r, c)
        if invited then row.apply:SetText("Invited"); row.apply:Disable()
        elseif pending then row.apply:SetText("Applied"); row.apply:Disable()
        elseif not canApply then row.apply:SetText("+? key"); row.apply:Disable()  -- key unknown
        else row.apply:SetText("Apply"); row.apply:Enable() end

        row:ClearAllPoints(); row:SetPoint("TOPLEFT", LX + 4, -y)
        row:Show(); row.apply:Show(); y = y + 19
    end
    for i = n + 1, #self.resultRows do self.resultRows[i]:Hide(); self.resultRows[i].apply:Hide() end

    return y
end

-- --------------------------------------------------------- Settings render -
function UI:RenderSettings()
    local y = 4
    -- (auto-apply + pending-count live on the Queue tab; HideAll keeps them hidden here)
    self.stMaxApps:Show(LX, y, 250);  y = y + 24
    self.stMinScore:Show(LX, y, 250); y = y + 24
    self.stBlack:Show(LX, y, 250);    y = y + 24
    self.chkGated:Show(LX, y);        y = y + 24
    self.chkUnknown:Show(LX, y);      y = y + 24
    self.chkMinimap:Show(LX, y);      y = y + 24
    self.chkOwnSearch:Show(LX, y);    y = y + 26
    self.clearBlBtn:ClearAllPoints(); self.clearBlBtn:SetPoint("TOPLEFT", LX, -y); self.clearBlBtn:Show(); y = y + 30

    self.s_scaleLabel:ClearAllPoints(); self.s_scaleLabel:SetPoint("TOPLEFT", LX, -y)
    self.s_scaleLabel:SetText("Panel scale: " .. math.floor((ns.db.scale or 1) * 100 + 0.5) .. "%")
    self.s_scaleLabel:Show(); y = y + 18
    self.s_scaleSlider:ClearAllPoints(); self.s_scaleSlider:SetPoint("TOPLEFT", LX, -y)
    self.s_scaleSlider:SetValue(ns.db.scale or 1); self.s_scaleSlider:Show(); y = y + 26

    self.s_help:ClearAllPoints(); self.s_help:SetPoint("TOPLEFT", LX, -y)
    self.s_help:SetText(GREY ..
        "KeyQueue searches the Premade Group Finder, keeps your chosen number of " ..
        "applications pending, and stops the moment a group invites you (sound + flash). " ..
        "Declines blacklist that leader for a while so it moves on.\n\n" ..
        "Auto-apply is best-effort: if Blizzard rate-limits scripted applies, use the " ..
        "Apply buttons on the Listings tab (one click each -- always allowed).\n\n" ..
        "Slash: /kq (toggle) - /kq start - /kq stop - /kq auto - /kq debug" .. R)
    self.s_help:Show()
    y = y + self.s_help:GetStringHeight() + 8

    return y
end

-- ----------------------------------------------------------------- Debug ---
function UI:Debug()
    local function p(...) print("|cff66ccffKeyQueue|r", ...) end
    p("--- KeyQueue debug ---")

    -- 1) search plumbing
    local hasSearch = (C_LFGList and C_LFGList.Search) and true or false
    local hasApply  = (C_LFGList and C_LFGList.ApplyToGroup) and true or false
    ns.Search:DiscoverActivities()
    local nact = 0; if ns.Search.mplusSet then for _ in pairs(ns.Search.mplusSet) do nact = nact + 1 end end
    p("Search api:", tostring(hasSearch), "| ApplyToGroup api:", tostring(hasApply),
        "| category:", tostring(ns.Search:Category()), "| M+ activities found:", nact)

    -- 2) kick a search and read what comes back (raw category vs M+-only)
    ns.Search:Kick()
    local rawN = 0
    if C_LFGList and C_LFGList.GetSearchResults then
        local a, b = C_LFGList.GetSearchResults()
        local rt = (type(a) == "table" and a) or (type(b) == "table" and b)
        rawN = (type(rt) == "table" and #rt) or (type(a) == "number" and a) or 0
    end
    local res = ns.Search:Read()
    p("raw category listings:", rawN, "| Mythic+ listings:", #res)

    -- dump the raw fields of the first listing so we can see where the "+19" title
    -- actually lives (field names vary by build) and confirm the key is parseable
    if res[1] and C_LFGList and C_LFGList.GetSearchResultInfo then
        local raw = C_LFGList.GetSearchResultInfo(res[1].resultID)
        if type(raw) == "table" then
            p("raw fields of first listing:")
            for k, v in pairs(raw) do
                local tv = type(v)
                if tv == "string" or tv == "number" or tv == "boolean" then
                    p("    " .. tostring(k) .. " = " .. (tv == "string" and ('"' .. v .. '"') or tostring(v)))
                end
            end
        end
    end

    -- 3) criteria + your score
    local c = ns.Filter:Criteria()
    local ctx = ns.Queue:Ctx()
    local ndun = 0
    if c.dungeons then for _ in pairs(c.dungeons) do ndun = ndun + 1 end else ndun = #ns.Dungeons.order end
    p("role:", c.role, "| key +" .. c.minKey .. "-" .. c.maxKey, "| target dungeons:", ndun,
        "| your M+ score:", ctx.myScore, "| skipGated:", tostring(c.skipGated),
        "| pending:", ns.Queue:Pending())

    -- 4) classify each listing; show the first few + tally why the rest were dropped
    local reasons, matched = {}, 0
    for i, r in ipairs(res) do
        local ok, why = ns.Filter:Match(r, c, ctx)
        if ok then matched = matched + 1 else reasons[why] = (reasons[why] or 0) + 1 end
        if i <= 6 then
            p(string.format("  [%s] +%s  %s  Hopen=%s  req=%s  %s",
                tostring(r.abbr), tostring(r.keyLevel), tostring(r.leaderName),
                tostring(r.healOpen), tostring(r.requiredScore),
                ok and "MATCH" or ("skip:" .. tostring(why))))
            if i <= 3 then
                -- raw text so we can see whether the "+N" is even present to parse
                p(string.format("      name=%q  comment=%q", tostring(r.name), tostring(r.comment)))
            end
        end
    end
    p("MATCHED:", matched)
    local rs = {}; for k, v in pairs(reasons) do rs[#rs + 1] = k .. "=" .. v end
    if #rs > 0 then p("dropped:", table.concat(rs, "  ")) end

    -- 5) plain-language verdict
    if #res == 0 then
        p(">> No M+ listings seen. If groups ARE listed in Group Finder, C_LFGList.Search")
        p(">> isn't returning for this build (signature/category). Tell me this line.")
    elseif matched == 0 then
        p(">> Listings exist but none pass the filter (see 'dropped' above). Common fixes:")
        p(">> widen the key range, tick 'Apply to unreadable key' in Settings, or check score/gating.")
    elseif not hasApply then
        p(">> Matches found but ApplyToGroup API is missing -- cannot apply.")
    else
        p(">> " .. matched .. " match(es). If auto-apply ran but 'pending' stays 0, scripted")
        p(">> applies are being blocked -- use the Listings Apply button (a real click).")
    end

    -- 6) progress snapshot
    p("progress loaded:", tostring(ns.Progress:Loaded()))
    local prog = {}
    for _, key in ipairs(ns.Dungeons.order) do
        prog[#prog + 1] = ns.Dungeons.list[key].abbr .. "+" .. ns.Progress:BestLevel(key)
    end
    p("season best:", table.concat(prog, " "))
end

-- /kq apps -- list your live outgoing applications + their server status, so you can
-- confirm an apply actually registered (status "applied" = pending, "invited" = they
-- want you, "declined"/"cancelled"/"timedout" = gone).
function UI:DumpApps()
    local function p(...) print("|cff66ccffKeyQueue|r", ...) end
    if not (C_LFGList and C_LFGList.GetApplications) then p("LFG API unavailable"); return end
    local ok, apps = pcall(C_LFGList.GetApplications)
    if not ok or type(apps) ~= "table" or #apps == 0 then
        p("No active applications right now. (Apply to a group, then re-run /kq apps.)")
        return
    end
    p(#apps .. " active application(s):")
    for _, appID in ipairs(apps) do
        local _, status, pending = ns.Queue:AppStatus(appID)
        local info = C_LFGList.GetSearchResultInfo and C_LFGList.GetSearchResultInfo(appID)
        local who = (type(info) == "table" and (info.name or info.leaderName)) or ("result " .. tostring(appID))
        p("  " .. tostring(who) .. "  -- status: " .. tostring(status) ..
            ((pending and pending ~= status) and ("  (pending: " .. tostring(pending) .. ")") or ""))
    end
end

-- /kq raw -- dump EVERY field of the first couple of live listings + their member
-- counts, so we can see exactly where the keystone level and role data live.
function UI:DumpRaw()
    local function p(...) print("|cff66ccffKeyQueue|r", ...) end
    if not (C_LFGList and C_LFGList.GetSearchResults and C_LFGList.GetSearchResultInfo) then
        p("LFG API unavailable"); return
    end
    local a, b = C_LFGList.GetSearchResults()
    local results = (type(a) == "table" and a) or (type(b) == "table" and b)
    if type(results) ~= "table" or #results == 0 then
        p("No results. Open Blizzard's Group Finder, search your dungeons, then /kq raw.")
        return
    end
    p(("dumping first %d of %d listings:"):format(math.min(2, #results), #results))
    for i = 1, math.min(2, #results) do
        local rid = results[i]
        local raw = C_LFGList.GetSearchResultInfo(rid)
        if type(raw) == "table" then
            local fld = {}
            for k, v in pairs(raw) do
                local tv = type(v)
                if tv == "number" or tv == "boolean" then
                    fld[#fld + 1] = tostring(k) .. "=" .. tostring(v)
                elseif tv == "string" and v ~= "" then
                    fld[#fld + 1] = tostring(k) .. '="' .. v .. '"'
                end
            end
            table.sort(fld)
            p(i .. ": " .. table.concat(fld, "  "))
        end
        if C_LFGList.GetSearchResultMemberCounts then
            local mc = C_LFGList.GetSearchResultMemberCounts(rid)
            if type(mc) == "table" then
                local m = {}
                for k, v in pairs(mc) do m[#m + 1] = tostring(k) .. "=" .. tostring(v) end
                table.sort(m)
                p("   memberCounts: " .. table.concat(m, "  "))
            end
        end
    end
end

-- ----------------------------------------------------------------- refresh -
function UI:Refresh()
    local f = self.frame
    if not f then return end

    -- state pill in the header
    local q = ns.Queue
    if q.invitedBy then self.statePill:SetText(GREEN .. "INVITED" .. R)
    elseif q.active then self.statePill:SetText(GREEN .. "\226\151\143 queueing" .. R)
    else self.statePill:SetText(GREY .. "idle" .. R) end

    -- always-visible header Start/Stop (works on every tab, can't be scrolled away)
    if self.headerStart then
        local a = q.active
        self.headerStart.bg:SetColorTexture(a and 0.70 or 0.18, a and 0.20 or 0.55, a and 0.20 or 0.28, 0.95)
        self.headerStart.text:SetText(a and "Stop" or "Start")
        self.headerStart.text:SetTextColor(1, 1, 1)
    end
    self:UpdateMinimap()

    self:HideAll()
    self:UpdateTabs()

    local tab = ns.db.tab or "queue"
    -- render the active tab defensively: a hiccup in one tab can't blank the panel
    -- (or the header Start button) or spam errors.
    local okR, res = pcall(function()
        if tab == "listings" then return self:RenderListings()
        elseif tab == "settings" then return self:RenderSettings()
        else return self:RenderQueue() end
    end)
    local bottom = (okR and res) or 40
    if not okR and not self._renderErrShown then
        self._renderErrShown = true
        print("|cff66ccffKeyQueue|r render error (" .. tostring(tab) .. "): " .. tostring(res))
    end

    local contentH = (bottom or 10) + 6
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

    if self.updatedText then self.updatedText:SetText(GREY .. (date and date("%H:%M:%S") or "") .. R) end
end
