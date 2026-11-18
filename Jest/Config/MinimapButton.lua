-- Minimap button: the Jest icon on the minimap's edge. Left-click opens the editor; drag it
-- round the edge to move it. Built by hand in the style of LibDBIcon (the addon uses no
-- libraries). Its position and visibility are account-wide (JestDB.minimap), not per profile.
local addonName, ns = ...

local Button = {}
ns.MinimapButton = Button

local EDGE_OFFSET = 5     -- how far outside the minimap's edge the button's centre sits

local button

local function settings()
	return JestDB.minimap
end

-- Place the button on the minimap's edge at its saved angle.
local function place()
	local a = math.rad(settings().angle)
	local r = (Minimap:GetWidth() or 140) / 2 + EDGE_OFFSET
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- While dragging: follow the cursor round the edge.
local function followCursor()
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local scale = Minimap:GetEffectiveScale()
	local x, y = GetCursorPosition()
	settings().angle = math.deg(math.atan2(y / scale - my, x / scale - mx)) % 360
	place()
end

local function create()
	button = CreateFrame("Button", "JestMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(24, 24)
	background:SetPoint("CENTER")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Media\\icon")
	ns.WheelView.AddCircleMask(button, icon)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT") -- the border art has its ring offset inside the texture
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnClick", function() ns.Panel.Toggle() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", followCursor)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Jest", 1, 0.82, 0) -- the game's standard gold-yellow (NORMAL_FONT_COLOR)
		GameTooltip:AddLine("Click to open settings", 1, 1, 1)
		GameTooltip:AddLine("Drag to reposition", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Show or hide the button to match the saved setting (creating it the first time it's shown).
function Button.Update()
	if not Minimap then return end
	if settings().hide then
		if button then button:Hide() end
		return
	end
	if not button then create() end
	place()
	button:Show()
end

function Button.IsShown()
	return not settings().hide
end

function Button.SetShown(show)
	settings().hide = not show
	Button.Update()
end

-- Called once the saved variables are loaded.
function Button.Init()
	Button.Update()
end

Button._button = function() return button end -- internal; used by the tests
Button._followCursor = followCursor
