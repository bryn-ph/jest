-- Icon picker popup: a paged grid over every icon the client knows (via Blizzard's
-- IconDataProviderMixin, the same source as the macro icon picker), plus manual entry.
local _, ns = ...

local Picker = {}
ns.IconPicker = Picker

local COLS, ROWS, SIZE, GAP = 10, 6, 36, 4
local PAGE = COLS * ROWS

local frame, buttons, pageText, manualBox
local icons -- cached for the session; building it walks tens of thousands of icons
local offset = 0
local current, onPick

local function buildIconList()
	local list, seen = {}, {}
	local function add(icon)
		if icon and not seen[icon] then
			seen[icon] = true
			list[#list + 1] = icon
		end
	end

	-- Curated emote icons first, in default-wheel order, so they're easy to find again.
	for _, s in ipairs(ns.Defaults.profile.wheels[1].slices) do
		add(ns.EmoteIcons[s.value])
	end
	add(ns.KindIcons.text)
	add(ns.KindIcons.macro)

	if IconDataProviderMixin and CreateAndInitFromMixin and IconDataProviderExtraType then
		local ok, provider = pcall(CreateAndInitFromMixin, IconDataProviderMixin, IconDataProviderExtraType.None)
		if ok and provider then
			for i = 1, provider:GetNumIcons() do
				add(provider:GetIconByIndex(i))
			end
			provider:Release()
		else
			ns.Debug("IconDataProvider failed:", tostring(provider))
		end
	elseif GetMacroIcons then
		local t = {}
		GetMacroIcons(t)
		if GetMacroItemIcons then GetMacroItemIcons(t) end
		for _, icon in ipairs(t) do
			add(icon)
		end
	end
	return list
end

local function maxOffset()
	local rows = math.ceil(#icons / COLS)
	return math.max(0, (rows - ROWS) * COLS)
end

local function render()
	for k, b in ipairs(buttons) do
		local icon = icons[offset + k]
		if icon then
			b.value = icon
			b.icon:SetTexture(icon)
			b.sel:SetShown(icon == current)
			b:Show()
		else
			b:Hide()
		end
	end
	local last = math.min(offset + PAGE, #icons)
	pageText:SetText(("%d-%d of %d"):format(#icons > 0 and offset + 1 or 0, last, #icons))
end

local function scrollBy(delta)
	offset = math.min(maxOffset(), math.max(0, offset + delta))
	render()
end

local function choose(value)
	local callback = onPick
	frame:Hide() -- OnHide clears onPick
	if callback and value then
		callback(value)
	end
end

local function create()
	frame = CreateFrame("Frame", "JestIconPicker", UIParent, "BackdropTemplate")
	frame:SetSize(COLS * (SIZE + GAP) + 28, ROWS * (SIZE + GAP) + 120)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:Hide()
	table.insert(UISpecialFrames, "JestIconPicker") -- Esc closes it

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -18)
	title:SetText("Choose an icon")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	buttons = {}
	for r = 1, ROWS do
		for c = 1, COLS do
			local b = CreateFrame("Button", nil, frame)
			b:SetSize(SIZE, SIZE)
			b:SetPoint("TOPLEFT", 14 + (c - 1) * (SIZE + GAP), -42 - (r - 1) * (SIZE + GAP))
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetAllPoints()
			b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			b.sel = b:CreateTexture(nil, "OVERLAY")
			b.sel:SetAllPoints()
			b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
			b.sel:SetBlendMode("ADD")
			b.sel:Hide()
			b:SetScript("OnClick", function(self) choose(self.value) end)
			buttons[#buttons + 1] = b
		end
	end

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) scrollBy(-delta * COLS) end)

	local gridBottom = -42 - ROWS * (SIZE + GAP)

	local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	prev:SetSize(32, 22)
	prev:SetPoint("TOPLEFT", 14, gridBottom - 4)
	prev:SetText("<")
	prev:SetScript("OnClick", function() scrollBy(-PAGE) end)

	local nextB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	nextB:SetSize(32, 22)
	nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
	nextB:SetText(">")
	nextB:SetScript("OnClick", function() scrollBy(PAGE) end)

	pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pageText:SetPoint("LEFT", nextB, "RIGHT", 8, 0)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPRIGHT", -18, gridBottom - 10)
	hint:SetText("Mouse wheel scrolls")

	local manualLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	manualLabel:SetPoint("TOPLEFT", 18, gridBottom - 36)
	manualLabel:SetText("Or type an icon name, path or file ID:")

	manualBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	manualBox:SetSize(260, 20)
	manualBox:SetPoint("TOPLEFT", manualLabel, "BOTTOMLEFT", 4, -4)
	manualBox:SetAutoFocus(false)

	local use = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	use:SetSize(70, 22)
	use:SetPoint("LEFT", manualBox, "RIGHT", 8, 0)
	use:SetText("Use")

	local function useManual()
		local icon = ns.Slices.ParseIcon(manualBox:GetText())
		if icon then choose(icon) end
	end
	use:SetScript("OnClick", useManual)
	manualBox:SetScript("OnEnterPressed", useManual)

	frame:SetScript("OnHide", function()
		onPick = nil
	end)
end

-- Open next to `anchor`; `callback(icon)` receives a fileID or texture path.
function Picker.Open(anchor, currentIcon, callback)
	if not frame then create() end
	icons = icons or buildIconList()
	current = currentIcon
	onPick = callback

	offset = 0
	if currentIcon then
		for i, icon in ipairs(icons) do
			if icon == currentIcon then
				offset = math.floor((i - 1) / COLS) * COLS
				break
			end
		end
		offset = math.min(offset, maxOffset())
	end

	manualBox:SetText("")
	frame:ClearAllPoints()
	if anchor then
		frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 0)
	else
		frame:SetPoint("CENTER")
	end
	frame:Show()
	render()
end

function Picker.Close()
	if frame then frame:Hide() end
end
