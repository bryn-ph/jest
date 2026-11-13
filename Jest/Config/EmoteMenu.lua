-- Emote dropdown list: every emote the client knows, with a search box. Opens under an anchor
-- (the panel's emote dropdown button); picking calls back with the emote token.
--   ns.EmoteMenu.Open(anchor, currentToken, onPick)   ns.EmoteMenu.Close()
-- Keyboard: type to filter, Up/Down to move, Enter to pick, Esc to close. Mouse wheel scrolls.
local _, ns = ...

local Menu = {}
ns.EmoteMenu = Menu

local ROWS = 10
local ROW_H = 20
local PAD = 6
local SEARCH_H = 22
local MIN_WIDTH = 300

local frame, search, rows, thumb, countText, legend
local entries = {}  -- current (filtered) list of { token, cmd }
local offset = 0    -- index of the first visible entry minus one
local cursor = 0    -- keyboard-highlighted entry index (0 = none)
local current, onPick, anchorFrame

local function maxOffset()
	return math.max(0, #entries - ROWS)
end

local function render()
	for k, row in ipairs(rows) do
		local i = offset + k
		local e = entries[i]
		if e then
			row.index = i
			row.token = e.token
			row.text:SetText(ns.Emotes.Label(e.token))
			row.cmd:SetText(e.cmd or "")
			row.badges:SetEmote(e.token)
			row.current:SetShown(e.token == current)
			row.sel:SetShown(i == cursor)
			row:Show()
		else
			row:Hide()
		end
	end
	if #entries == 0 then
		countText:SetText("No emotes match")
	else
		countText:SetText(("%d emote%s"):format(#entries, #entries == 1 and "" or "s"))
	end
	-- Scroll thumb: proportional size and position along the track.
	local trackH = ROWS * ROW_H
	if #entries > ROWS then
		local h = math.max(12, trackH * ROWS / #entries)
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -(PAD + SEARCH_H + 4) - (trackH - h) * (offset / maxOffset()))
		thumb:Show()
	else
		thumb:Hide()
	end
end

local function scrollTo(i)
	if i <= offset then
		offset = i - 1
	elseif i > offset + ROWS then
		offset = i - ROWS
	end
	offset = math.min(maxOffset(), math.max(0, offset))
end

local function setCursor(i)
	if #entries == 0 then
		cursor = 0
	else
		cursor = math.min(#entries, math.max(1, i))
		scrollTo(cursor)
	end
	render()
end

local function filter()
	local q = search:GetText()
	if q == "" then
		entries = ns.Emotes.All()
	else
		entries = ns.Emotes.Search(q, 10000)
	end
	offset = 0
	setCursor(1)
end

local function pick(token)
	local callback = onPick
	Menu.Close()
	if callback and token then callback(token) end
end

local function create()
	frame = CreateFrame("Frame", "JestEmoteMenu", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	frame:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
	frame:SetBackdropBorderColor(1, 0.82, 0, 0.6)
	frame:SetHeight(PAD + SEARCH_H + 4 + ROWS * ROW_H + 18 + PAD)
	frame:Hide()
	table.insert(UISpecialFrames, "JestEmoteMenu") -- Esc closes it

	search = ns.Widgets.Input(frame, 100)
	search.debugName = "emoteSearch"
	search:SetPoint("TOPLEFT", PAD, -PAD)
	search:SetPoint("TOPRIGHT", -PAD, -PAD)
	ns.Widgets.SetPlaceholder(search, "Search emotes")
	search:HookScript("OnTextChanged", function(_, userInput)
		if userInput then filter() end
	end)
	search:SetScript("OnArrowPressed", function(_, key)
		if key == "DOWN" then setCursor(cursor + 1) elseif key == "UP" then setCursor(cursor - 1) end
	end)
	search:SetScript("OnEnterPressed", function()
		local e = entries[cursor]
		if e then pick(e.token) end
	end)
	search:SetScript("OnEscapePressed", function() Menu.Close() end)

	rows = {}
	for k = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", PAD, -(PAD + SEARCH_H + 4) - (k - 1) * ROW_H)
		row:SetPoint("TOPRIGHT", -PAD - 6, -(PAD + SEARCH_H + 4) - (k - 1) * ROW_H)
		row.current = row:CreateTexture(nil, "BACKGROUND")
		row.current:SetAllPoints()
		row.current:SetColorTexture(1, 0.82, 0, 0.12)
		row.sel = row:CreateTexture(nil, "BORDER")
		row.sel:SetAllPoints()
		row.sel:SetColorTexture(1, 0.82, 0, 0.25)
		local hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.08)
		-- Right to left: Anim/Voice tags (fixed columns), slash command, then the name.
		row.badges = ns.Widgets.EmoteBadges(row)
		row.badges:SetPoint("RIGHT", -6, 0)
		row.cmd = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.cmd:SetPoint("RIGHT", row.badges, "LEFT", -8, 0)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetPoint("RIGHT", row.cmd, "LEFT", -6, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self) pick(self.token) end)
		rows[k] = row
	end

	local track = frame:CreateTexture(nil, "BORDER")
	track:SetColorTexture(1, 1, 1, 0.06)
	track:SetWidth(3)
	track:SetPoint("TOPRIGHT", -3, -(PAD + SEARCH_H + 4))
	track:SetHeight(ROWS * ROW_H)
	thumb = frame:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(1, 0.82, 0, 0.6)
	thumb:SetWidth(3)

	countText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	countText:SetPoint("BOTTOMLEFT", PAD + 2, PAD)
	legend = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	legend:SetPoint("BOTTOMRIGHT", -PAD - 2, PAD)
	legend:SetText(ns.Widgets.EmoteBadgeLegend())

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.min(maxOffset(), math.max(0, offset - delta * 3))
		render()
	end)

	-- Close when clicking anywhere outside the menu (or its dropdown button).
	frame:SetScript("OnEvent", function(self)
		if not self:IsMouseOver() and not (anchorFrame and anchorFrame:IsMouseOver()) then
			Menu.Close()
		end
	end)
	frame:SetScript("OnShow", function(self)
		pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
	end)
	frame:SetScript("OnHide", function(self)
		pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
		onPick = nil
	end)
end

function Menu.IsOpen()
	return frame ~= nil and frame:IsShown()
end

-- Open under `anchor`; `callback(token)` receives the picked emote token.
function Menu.Open(anchor, currentToken, callback)
	if not frame then create() end
	current = currentToken
	onPick = callback
	anchorFrame = anchor

	search:SetText("")
	entries = ns.Emotes.All()
	offset, cursor = 0, 0
	for i, e in ipairs(entries) do
		if e.token == currentToken then
			cursor = i
			break
		end
	end
	if cursor == 0 then cursor = 1 end
	-- Centre the current emote in the list when possible.
	offset = math.min(maxOffset(), math.max(0, cursor - math.ceil(ROWS / 2)))

	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	frame:SetWidth(math.max(MIN_WIDTH, anchor:GetWidth() or MIN_WIDTH))
	frame:Show()
	render()
	search:SetFocus()
end

function Menu.Close()
	if frame then frame:Hide() end
end

Menu._ui = function() return { frame = frame, search = search, rows = rows } end -- for tests
