-- Icon picker popup: a paged grid over every icon the client knows (via Blizzard's
-- IconDataProviderMixin, the same source as the macro icon picker), with a search box and
-- category chips. Icon names come from Config/IconData.lua (generated), since the client only
-- gives addons bare file IDs.
local _, ns = ...

local Picker = {}
ns.IconPicker = Picker

local COLS, ROWS, SIZE, GAP = 10, 6, 36, 4
local PAGE = COLS * ROWS
local PAD = 18                 -- frame edge to content
local GRID_TOP = -104
local GRID_H = ROWS * (SIZE + GAP) - GAP
local SCROLL_W, SCROLL_GAP, SCROLL_THUMB_MIN = 10, 8, 24
local SEARCH_PLACEHOLDER = "Search, e.g. dance, heart, beer"

local FILTERS = {
	{ value = "abilities", text = "Abilities" },
	{ value = "achievements", text = "Achievements" },
	{ value = "items", text = "Items" },
	{ value = "all", text = "All" },
}
local FILTER_TEXT = {}
for _, f in ipairs(FILTERS) do FILTER_TEXT[f.value] = f.text end

local frame, buttons, pageText, searchBox, filterSwitch, scrollBar
local icons    -- every icon, cached for the session; building it walks tens of thousands
local view     -- the icons shown: filtered by category and search
local nameOf   -- [fileID] = icon name, parsed from ns.IconNames on first use
local lowerOf  -- [fileID] = lower-cased name, so searching doesn't lower 30,000 names per key
local filter = "abilities"
local offset = 0
local current, onPick

---------------------------------------------------------------------------
-- Names and categories
---------------------------------------------------------------------------
local function loadNames()
	if nameOf then return end
	nameOf, lowerOf = {}, {}
	for id, name in (ns.IconNames or ""):gmatch("(%d+) ([^\n]+)") do
		id = tonumber(id)
		nameOf[id], lowerOf[id] = name, name:lower()
	end
	ns.IconNames = nil -- parsed; the tables above hold the names now
end

-- Icon name for a file ID or a texture path ("Interface\\Icons\\Foo" -> "Foo"), or nil.
local function iconName(icon)
	if type(icon) == "number" then return nameOf[icon] end
	if type(icon) == "string" then return icon:match("([^\\/]+)$") end
end

-- Items are INV_*; achievements Achievement_*; everything else (spells, abilities, UI...) counts
-- as an ability. Icons without a known name only show under All.
local function categoryOf(name)
	if not name then return nil end
	local prefix = (name:match("^([^_]+)") or ""):lower()
	if prefix == "inv" or prefix == "ivn" or prefix == "item" then return "items" end
	if prefix == "achievement" then return "achievements" end
	return "abilities"
end
Picker._categoryOf = categoryOf -- internal; used by the tests

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

---------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------
local hiddenMatches = 0 -- search matches in other categories (for the "N in All" hint)

-- Every search word must appear in the name. Ranking: an exact name first, then names where
-- more words start at a word boundary ("dance" in Ability_Rogue_ShadowDance beats
-- "dance" in INV_Misc_FireDancer), then the game's own order.
local function refilter()
	local query = searchBox and searchBox:GetText() or ""
	local terms = {}
	for word in query:lower():gmatch("%S+") do
		terms[#terms + 1] = word
	end
	local wanted = tonumber(query)
	local whole = query:lower():gsub("^%s+", ""):gsub("%s+$", "")

	view, hiddenMatches = {}, 0
	local score, order = {}, {}
	for i, icon in ipairs(icons) do
		local name = iconName(icon)
		local matches, points = true, 0
		if wanted then
			matches = icon == wanted
		elseif #terms > 0 then
			local lower = (type(icon) == "number" and lowerOf[icon]) or (name and name:lower())
			if not lower then
				matches = false
			else
				for _, term in ipairs(terms) do
					local at = lower:find(term, 1, true)
					if not at then
						matches = false
						break
					end
					local before = at > 1 and name:sub(at - 1, at - 1) or ""
					if at == 1 or before:match("[_%s%-]") or name:sub(at, at):match("%u") then
						points = points + 1
					end
				end
				if lower == whole then points = points + 100 end
			end
		end
		if matches then
			if wanted or filter == "all" or categoryOf(name) == filter then
				view[#view + 1] = icon
				score[icon], order[icon] = points, i
			else
				hiddenMatches = hiddenMatches + 1
			end
		end
	end
	if #terms > 0 and not wanted then
		table.sort(view, function(a, b)
			if score[a] ~= score[b] then return score[a] > score[b] end
			return order[a] < order[b]
		end)
	end
end

local function maxOffset()
	local rows = math.ceil(#view / COLS)
	return math.max(0, (rows - ROWS) * COLS)
end

-- Move the scroll bar to match `offset` (one step per row of icons). `syncing` stops its
-- OnValueChanged from scrolling the grid back while we set it.
local syncing = false
local function syncScrollBar()
	local rows = maxOffset() / COLS
	syncing = true
	scrollBar:SetMinMaxValues(0, math.max(rows, 0))
	scrollBar:SetValue(offset / COLS)
	syncing = false
	scrollBar:SetShown(rows > 0)
	local thumb = scrollBar:GetThumbTexture()
	if thumb then
		local total = rows + ROWS
		thumb:SetHeight(math.max(SCROLL_THUMB_MIN, GRID_H * ROWS / total))
	end
end

local function render()
	syncScrollBar()
	for k, b in ipairs(buttons) do
		local icon = view[offset + k]
		if icon then
			b.value = icon
			b.icon:SetTexture(icon)
			b.sel:SetShown(icon == current)
			b:Show()
		else
			b:Hide()
		end
	end
	if #view > 0 then
		pageText:SetText(("%d-%d of %d"):format(offset + 1, math.min(offset + PAGE, #view), #view))
	elseif hiddenMatches > 0 then
		pageText:SetText(("No matches in %s; %d in other categories. Try All."):format(FILTER_TEXT[filter], hiddenMatches))
	else
		pageText:SetText("No icons match.")
	end
end

local function scrollBy(delta)
	offset = math.min(maxOffset(), math.max(0, offset + delta))
	render()
end

local function update()
	refilter()
	offset = 0
	render()
end

local function setFilter(value)
	filter = value
	filterSwitch:SetValue(value)
	update()
end

local function choose(value)
	local callback = onPick
	frame:Hide() -- OnHide clears onPick
	if callback and value then
		callback(value)
	end
end

-- Enter: a file ID or texture path is used as typed; otherwise take the best match.
local function chooseFromSearch()
	local text = searchBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
	if tonumber(text) or text:find("[\\/]") then
		local icon = ns.Slices.ParseIcon(text)
		if icon then choose(icon) end
	elseif view[1] then
		choose(view[1])
	end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function iconTooltip(b)
	local name = iconName(b.value)
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	GameTooltip:SetText(name and name:gsub("_", " ") or "Icon", 1, 1, 1)
	if type(b.value) == "number" then
		GameTooltip:AddLine("File ID " .. b.value, 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function create()
	local gridW = COLS * (SIZE + GAP) - GAP
	frame = CreateFrame("Frame", "JestIconPicker", UIParent, "BackdropTemplate")
	frame:SetSize(gridW + SCROLL_GAP + SCROLL_W + 2 * PAD, -GRID_TOP + ROWS * (SIZE + GAP) + 64)
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

	local fullW = gridW + SCROLL_GAP + SCROLL_W
	searchBox = ns.Widgets.Input(frame, fullW)
	searchBox:SetPoint("TOPLEFT", PAD, -42)
	ns.Widgets.SetPlaceholder(searchBox, SEARCH_PLACEHOLDER)
	searchBox:HookScript("OnTextChanged", function() update() end)
	searchBox:SetScript("OnEnterPressed", chooseFromSearch)
	searchBox:SetScript("OnEscapePressed", function() frame:Hide() end)

	filterSwitch = ns.Widgets.Segmented(frame, FILTERS, fullW, setFilter)
	filterSwitch:SetPoint("TOPLEFT", PAD, -72)

	buttons = {}
	for r = 1, ROWS do
		for c = 1, COLS do
			local b = CreateFrame("Button", nil, frame)
			b:SetSize(SIZE, SIZE)
			b:SetPoint("TOPLEFT", PAD + (c - 1) * (SIZE + GAP), GRID_TOP - (r - 1) * (SIZE + GAP))
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetAllPoints()
			ns.CropIcon(b.icon)
			b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			b.sel = b:CreateTexture(nil, "OVERLAY")
			b.sel:SetAllPoints()
			b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
			b.sel:SetBlendMode("ADD")
			b.sel:Hide()
			b:SetScript("OnClick", function(self) choose(self.value) end)
			b:SetScript("OnEnter", iconTooltip)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			buttons[#buttons + 1] = b
		end
	end

	-- Scroll bar beside the grid: drag the thumb or click the track. One step per row.
	scrollBar = CreateFrame("Slider", nil, frame, "BackdropTemplate")
	scrollBar:SetOrientation("VERTICAL")
	scrollBar:SetSize(SCROLL_W, GRID_H)
	scrollBar:SetPoint("TOPLEFT", PAD + gridW + SCROLL_GAP, GRID_TOP)
	scrollBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	scrollBar:SetBackdropColor(0, 0, 0, 0.45)
	scrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
	local thumb = scrollBar:GetThumbTexture()
	if thumb then
		thumb:SetSize(SCROLL_W, 40)
		thumb:SetVertexColor(1, 0.82, 0.2, 0.75)
	end
	scrollBar:SetValueStep(1)
	if scrollBar.SetObeyStepOnDrag then scrollBar:SetObeyStepOnDrag(true) end
	scrollBar:SetScript("OnValueChanged", function(_, value)
		if syncing then return end
		local row = math.floor(value + 0.5)
		if row * COLS ~= offset then
			offset = math.min(maxOffset(), row * COLS)
			render()
		end
	end)

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) scrollBy(-delta * COLS) end)

	local gridBottom = GRID_TOP - ROWS * (SIZE + GAP)

	local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	prev:SetSize(32, 22)
	prev:SetPoint("TOPLEFT", PAD, gridBottom - 4)
	prev:SetText("<")
	prev:SetScript("OnClick", function() scrollBy(-PAGE) end)

	local nextB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	nextB:SetSize(32, 22)
	nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
	nextB:SetText(">")
	nextB:SetScript("OnClick", function() scrollBy(PAGE) end)

	pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pageText:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
	pageText:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	pageText:SetJustifyH("LEFT")
	pageText:SetWordWrap(false)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", PAD, gridBottom - 34)
	hint:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Enter picks the first icon. A file ID or texture path also works. Mouse wheel scrolls.")

	frame:SetScript("OnHide", function()
		onPick = nil
		searchBox:ClearFocus()
	end)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- Open next to `anchor`; `callback(icon)` receives a fileID or texture path. Starts on the
-- current icon's category (Abilities when there isn't one).
function Picker.Open(anchor, currentIcon, callback)
	if not frame then create() end
	loadNames()
	icons = icons or buildIconList()
	current = currentIcon
	onPick = callback

	searchBox:SetText("")
	filter = categoryOf(iconName(currentIcon)) or "abilities"
	filterSwitch:SetValue(filter)
	refilter()
	offset = 0
	if currentIcon then
		for i, icon in ipairs(view) do
			if icon == currentIcon then
				offset = math.min(math.floor((i - 1) / COLS) * COLS, maxOffset())
				break
			end
		end
	end

	frame:ClearAllPoints()
	if anchor then
		frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 0)
	else
		frame:SetPoint("CENTER")
	end
	frame:Show()
	render()
	searchBox:SetFocus() -- start typing straight away
end

function Picker.Close()
	if frame then frame:Hide() end
end

Picker._view = function() return view end -- internal; used by the tests
Picker._search = function(text) searchBox:SetText(text); update() end
Picker._setFilter = function(value) setFilter(value) end
Picker._enter = function() chooseFromSearch() end
Picker._scrollBar = function() return scrollBar end
