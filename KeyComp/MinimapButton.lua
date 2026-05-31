-- MinimapButton.lua — a self-contained minimap button (no LibDBIcon dependency,
-- matching this addon's no-library style).
--   Left-click  : toggle the panel
--   Right-click : toggle auto-open-while-forming
--   Drag        : move the button around the minimap rim (angle saved)
-- Visibility persists in ns.db.minimapHide; angle in ns.db.minimapAngle.
local addonName, ns = ...

local M = {}
ns.Minimap = M

local ICON = "Interface\\Icons\\Spell_Holy_DispelMagic" -- matches .toc IconTexture
local button

-- atan2 moved across Lua versions; cover both (5.1 math.atan2, 5.3+ math.atan/2).
local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

local function updatePosition()
    if not button or not Minimap then return end
    local angle = math.rad((ns.db and ns.db.minimapAngle) or 220)
    local r = (Minimap:GetWidth() / 2) + 5 -- just outside the rim, any minimap size
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    if ns.db then ns.db.minimapAngle = math.deg(atan2(py - my, px - mx)) end
    updatePosition()
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff66ccffKeyComp|r")
    GameTooltip:AddLine("|cffffffffLeft-click|r  toggle panel", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffRight-click|r toggle auto-open", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffDrag|r       move button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function M:Init()
    if button then self:Update(); return end
    if not Minimap then return end

    button = CreateFrame("Button", "KeyCompMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- This highlight art is a radial glow meant to be drawn additively; the
    -- HIGHLIGHT draw layer defaults to "BLEND", which renders its dark field as
    -- an ugly grey square on hover. "ADD" makes the dark parts vanish so only
    -- the soft glow shows (matches Blizzard's zoom buttons / LibDBIcon).
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(button)

    button:SetScript("OnClick", function(_, clicked)
        if clicked == "RightButton" then
            ns.db.autoShow = not ns.db.autoShow
            print("|cff66ccffKeyComp|r auto-open while forming: " .. (ns.db.autoShow and "ON" or "OFF"))
        elseif ns.UI then
            ns.UI:Toggle()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self:Update()
end

-- apply saved visibility + position
function M:Update()
    if not button then return end
    if ns.db and ns.db.minimapHide then button:Hide() else button:Show() end
    updatePosition()
end

-- toggle button visibility; returns the new shown state
function M:Toggle()
    if ns.db then ns.db.minimapHide = not ns.db.minimapHide end
    self:Update()
    return not (ns.db and ns.db.minimapHide)
end
