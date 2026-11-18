-- Shared UI widgets for the options panel and popups.
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}
local BORDER = { 0.4, 0.4, 0.4, 1 }
local BORDER_FOCUS = { 1, 0.82, 0, 1 }

local function setBorder(box, c)
	box:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
end

-- Single-line text input. A plain EditBox rather than InputBoxTemplate, whose edit boxes
-- ignore Backspace on WoW: Forever. Use HookScript (not SetScript) for focus handlers so the
-- focus styling below is kept.
-- Drawn with the game's own input-box border (InputBoxVisualTemplate: textures only, no scripts
-- or mixin), so it looks like any other WoW text box.
function Widgets.Input(parent, width, maxLetters)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxVisualTemplate")
	box:SetSize(width, 20)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(2, 6, 0, 0)
	box:SetAutoFocus(false)
	if maxLetters then
		box:SetMaxLetters(maxLetters)
	end
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
	return box
end

-- A dark box with the tooltip-style border the game uses for panels like the macro editor.
function Widgets.NativeBox(frame)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.6)
	frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

-- A button drawn like the game's dropdowns (WowStyle1DropdownTemplate's art). b.Text holds the
-- shown value; the caller sets OnClick (usually to open a Widgets.ShowMenu list).
function Widgets.Dropdown(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 25)
	b.Background = b:CreateTexture(nil, "BACKGROUND")
	b.Background:SetAtlas("common-dropdown-textholder")
	b.Background:SetPoint("TOPLEFT", -8, 7)
	b.Background:SetPoint("BOTTOMRIGHT", 8, -9)
	b.Arrow = b:CreateTexture(nil, "ARTWORK")
	b.Arrow:SetAtlas("common-dropdown-a-button", true)
	b.Arrow:SetPoint("RIGHT", 1, -3)
	b.Text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	b.Text:SetPoint("LEFT", 8, -1)
	b.Text:SetPoint("RIGHT", b.Arrow, "LEFT", -2, 0)
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	b:SetScript("OnEnter", function(self) self.Arrow:SetAtlas("common-dropdown-a-button-hover", true) end)
	b:SetScript("OnLeave", function(self) self.Arrow:SetAtlas("common-dropdown-a-button", true) end)
	b:SetScript("OnMouseDown", function(self) self.Arrow:SetAtlas("common-dropdown-a-button-pressedhover", true) end)
	b:SetScript("OnMouseUp", function(self) self.Arrow:SetAtlas("common-dropdown-a-button-hover", true) end)
	return b
end

-- A labelled checkbox (UICheckButtonTemplate). get() reads the value, set(on) stores it;
-- check:Refresh() re-reads it.
function Widgets.Check(parent, text, tooltipText, get, set)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check.label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	check.label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	check.label:SetText(text)
	check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	check:SetScript("OnEnter", function(self)
		if not tooltipText then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, 1, 1, 1)
		GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	function check:Refresh() self:SetChecked(get() and true or false) end
	check.set = set -- internal; used by the tests
	return check
end

-- A labelled slider with steppers, like the game's Settings (MinimalSliderWithSteppersTemplate).
-- format(value) is the text shown on its right. get() reads, set(value) stores (already rounded
-- to the step); slider:Refresh() re-reads.
function Widgets.Slider(parent, text, minValue, maxValue, step, format, get, set)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(420, 26)
	holder.label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	holder.label:SetPoint("LEFT")
	holder.label:SetWidth(170)
	holder.label:SetJustifyH("LEFT")
	holder.label:SetText(text)
	local slider = CreateFrame("Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", holder.label, "RIGHT", 4, 0)
	slider:SetSize(240, 26)
	holder.slider = slider

	local function round(v)
		return math.floor((v - minValue) / step + 0.5) * step + minValue
	end
	holder.set = function(v) set(round(v)) end -- internal; used by the tests
	local formatters = {}
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		formatters[MinimalSliderWithSteppersMixin.Label.Right] = function(v) return format(round(v)) end
	end
	function holder:Refresh()
		self.refreshing = true
		slider:Init(get(), minValue, maxValue, (maxValue - minValue) / step, formatters)
		self.refreshing = false
	end
	if slider.RegisterCallback and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event then
		slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
			if not holder.refreshing then holder.set(v) end
		end, holder)
	end
	return holder
end

-- Grey hint text shown inside an input while it's empty.
function Widgets.SetPlaceholder(box, text)
	if not box.placeholder then
		local fs = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
		fs:SetPoint("LEFT", 2, 0)
		fs:SetPoint("RIGHT", -6, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		box.placeholder = fs
		box:HookScript("OnTextChanged", function(self)
			self.placeholder:SetShown(self:GetText() == "")
		end)
	end
	box.placeholder:SetText(text or "")
	box.placeholder:SetShown(box:GetText() == "")
end

-- Section title with a hairline running to the right edge of `parent`.
function Widgets.Header(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetText(text)
	fs:SetJustifyH("LEFT")
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.12)
	line:SetHeight(1)
	line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
	return fs
end

-- Subtle bordered panel used to group related controls.
function Widgets.Card(parent)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	card:SetBackdrop(BACKDROP)
	card:SetBackdropColor(1, 1, 1, 0.03)
	card:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
	return card
end

-- Row of mutually exclusive options. items = { { value = ..., text = ... }, ... };
-- onSelect(value) fires on click. holder.buttons[value] are the segments; holder:SetValue(v).
function Widgets.Segmented(parent, items, width, onSelect)
	local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	holder:SetSize(width, 24)
	holder:SetBackdrop(BACKDROP)
	holder:SetBackdropColor(0, 0, 0, 0.5)
	setBorder(holder, BORDER)
	holder.buttons = {}

	local segW = width / #items
	for i, item in ipairs(items) do
		local b = CreateFrame("Button", nil, holder)
		b:SetPoint("TOPLEFT", (i - 1) * segW + 1, -1)
		b:SetSize(segW - 2, 22)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(1, 0.82, 0, 0.25)
		b.bg:Hide()
		local hover = b:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.08)
		if i > 1 then
			local div = b:CreateTexture(nil, "BORDER")
			div:SetColorTexture(0.4, 0.4, 0.4, 1)
			div:SetWidth(1)
			div:SetPoint("TOPLEFT", -1, 0)
			div:SetPoint("BOTTOMLEFT", -1, 0)
		end
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(item.text)
		b:SetScript("OnClick", function() onSelect(item.value) end)
		holder.buttons[item.value] = b
	end

	function holder:SetValue(value)
		for v, b in pairs(self.buttons) do
			local on = v == value
			b.bg:SetShown(on)
			if on then
				b.text:SetTextColor(1, 1, 1)
			else
				b.text:SetTextColor(0.62, 0.62, 0.62)
			end
		end
	end

	return holder
end

-- Small coloured tag with a label.
local function pill(parent, text, color, width)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetSize(width, 14)
	f:EnableMouse(false)
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(color[1], color[2], color[3], 0.16)
	f:SetBackdropBorderColor(color[1], color[2], color[3], 0.55)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.text:SetPoint("CENTER", 0, 0)
	f.text:SetText(text)
	f.text:SetTextColor(color[1], color[2], color[3])
	return f
end

Widgets.ANIM_COLOR = { 0.4, 0.85, 0.95 }
Widgets.VOICE_COLOR = { 0.82, 0.6, 1 }
Widgets.NONE_COLOR = { 0.55, 0.55, 0.55 }
local PILL_W, PILL_GAP = 38, 4
Widgets.BADGES_WIDTH = PILL_W * 2 + PILL_GAP

-- "Anim" / "Voice" tags in fixed columns so they line up down a list, or "Text only".
-- holder:SetEmote(token) shows nothing for emotes missing from the data.
function Widgets.EmoteBadges(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(Widgets.BADGES_WIDTH, 14)
	holder:EnableMouse(false)
	holder.anim = pill(holder, "Anim", Widgets.ANIM_COLOR, PILL_W)
	holder.anim:SetPoint("LEFT")
	holder.voice = pill(holder, "Voice", Widgets.VOICE_COLOR, PILL_W)
	holder.voice:SetPoint("RIGHT")
	holder.none = pill(holder, "Text only", Widgets.NONE_COLOR, Widgets.BADGES_WIDTH)
	holder.none:SetPoint("CENTER")

	function holder:SetEmote(token)
		local known, anim, voice = ns.Emotes.Features(token)
		self.anim:SetShown(anim)
		self.voice:SetShown(voice)
		self.none:SetShown(known and not anim and not voice)
	end
	return holder
end

-- On/off chip styled like the tags. onChange(checked) fires on click; SetChecked doesn't call it.
function Widgets.ToggleChip(parent, text, color, width, onChange)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, 16)
	b:SetBackdrop(BACKDROP)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(text)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetPoint("TOPLEFT", 1, -1)
	hover:SetPoint("BOTTOMRIGHT", -1, 1)
	hover:SetColorTexture(1, 1, 1, 0.08)

	function b:SetChecked(on)
		self.checked = on and true or false
		local r, g, bl = color[1], color[2], color[3]
		if self.checked then
			self:SetBackdropColor(r, g, bl, 0.32)
			self:SetBackdropBorderColor(r, g, bl, 0.95)
			self.text:SetTextColor(1, 1, 1)
		else
			self:SetBackdropColor(r, g, bl, 0.05)
			self:SetBackdropBorderColor(r, g, bl, 0.35)
			self.text:SetTextColor(r * 0.75, g * 0.75, bl * 0.75)
		end
	end
	b:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		onChange(self.checked)
	end)
	b:SetChecked(false)
	return b
end

-- One-line key for the tags.
function Widgets.EmoteBadgeLegend()
	local function hex(c)
		return ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
	end
	return ("|cff%sAnim|r animation   |cff%sVoice|r your character speaks"):format(hex(Widgets.ANIM_COLOR), hex(Widgets.VOICE_COLOR))
end

-- Small pop-up menu under `anchor`. items = { item, ... } where an item is
--   { text =, onClick = fn, disabled = bool, checked = bool, tooltip = text,
--     onRemove = fn, removeTooltip = text }  -- onRemove adds an "x" button on the right
-- or { separator = true }. checked marks the current choice in gold. Closes on a pick, on Esc,
-- or on a click anywhere else; clicking an "x" leaves it open (the caller re-shows it).
-- Sized to its longest item.
local menu
local MENU_ROW_H, MENU_SEP_H, MENU_MIN_W, MENU_MAX_W, MENU_PAD, MENU_REMOVE_W = 20, 9, 140, 280, 26, 20

local function createMenu()
	menu = CreateFrame("Frame", "JestContextMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	menu:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
	menu:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
	menu:EnableMouse(true)
	menu:Hide()
	menu.rows = {}
	table.insert(UISpecialFrames, "JestContextMenu") -- Esc closes it
	-- Close on a click outside the menu. A click on the button that opened it is left to that
	-- button, which toggles: closing here first would make its click reopen the menu.
	menu:SetScript("OnEvent", function(self)
		if self:IsMouseOver() then return end
		if self.anchor and self.anchor:IsMouseOver() then return end
		self:Hide()
	end)
	menu:SetScript("OnShow", function(self)
		pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
	end)
	menu:SetScript("OnHide", function(self)
		pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
	end)
end

local function menuRow(i)
	local row = menu.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, menu)
	row:SetHeight(MENU_ROW_H)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 8, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 0.82, 0, 0.18)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(1, 1, 1, 0.12)
	row.line:SetHeight(1)
	row.line:SetPoint("LEFT", 6, 0)
	row.line:SetPoint("RIGHT", -6, 0)

	-- "x" on the right, for rows with onRemove.
	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(MENU_REMOVE_W, MENU_ROW_H)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.remove.text = row.remove:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.remove.text:SetPoint("CENTER")
	row.remove.text:SetText("\195\151") -- U+00D7 multiplication sign
	row.remove.text:SetTextColor(0.6, 0.6, 0.6)
	row.remove:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 0.3, 0.3)
		if row.removeTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(row.removeTooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	row.remove:SetScript("OnLeave", function(self)
		self.text:SetTextColor(0.6, 0.6, 0.6)
		GameTooltip:Hide()
	end)
	row.remove:SetScript("OnClick", function()
		GameTooltip:Hide()
		if row.onRemove then row.onRemove() end
	end)
	row:SetScript("OnClick", function(self)
		menu:Hide()
		if self.onClick then self.onClick() end
	end)
	row:SetScript("OnEnter", function(self)
		if not self.tooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetMotionScriptsWhileDisabled(true)
	menu.rows[i] = row
	return row
end

function Widgets.ShowMenu(anchor, items)
	if not menu then createMenu() end
	local width, y = MENU_MIN_W, -5
	for i, item in ipairs(items) do
		local row = menuRow(i)
		local height = item.separator and MENU_SEP_H or MENU_ROW_H
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 5, y)
		row:SetPoint("RIGHT", -5, 0)
		y = y - height

		row.line:SetShown(item.separator == true)
		row.text:SetText(item.separator and "" or item.text)
		row.onClick = item.onClick
		row.tooltip = item.tooltip
		row.onRemove, row.removeTooltip = item.onRemove, item.removeTooltip
		row.remove:SetShown(item.onRemove ~= nil)
		row.text:SetPoint("RIGHT", item.onRemove and -(MENU_REMOVE_W + 4) or -8, 0)
		row:SetEnabled(not (item.disabled or item.separator))
		if item.disabled then
			row.text:SetTextColor(0.45, 0.45, 0.45)
		elseif item.checked then
			row.text:SetTextColor(1, 0.82, 0)
		else
			row.text:SetTextColor(1, 1, 1)
		end
		local text = row.text
		local textWidth = (text.GetUnboundedStringWidth and text:GetUnboundedStringWidth()) or text:GetStringWidth() or 0
		width = math.max(width, textWidth + MENU_PAD + (item.onRemove and MENU_REMOVE_W or 0))
		row:Show()
	end
	for i = #items + 1, #menu.rows do
		menu.rows[i]:Hide()
	end
	menu:SetSize(math.min(MENU_MAX_W, width), -y + 5)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	menu.anchor = anchor
	menu:Show()
	menu:Raise()
end

function Widgets.CloseMenu()
	if menu then menu:Hide() end
end

function Widgets.MenuIsOpen()
	return menu ~= nil and menu:IsShown()
end

-- Small dialog asking for a name. Prompt(title, text, onAccept): onAccept(name) returns nothing
-- to close, or a message to show while staying open (e.g. "That name is taken").
local prompt

-- Title shown in a native window's title bar.
-- A template's child (parentKey), or nil when it doesn't exist.
local function child(frame, key)
	local v = rawget(frame, key)
	return type(v) == "table" and v or nil
end
Widgets.Child = child

function Widgets.SetTitle(frame, text)
	local container = child(frame, "TitleContainer")
	if frame.SetTitle then
		frame:SetTitle(text)
	elseif container and child(container, "TitleText") then
		container.TitleText:SetText(text)
	end
end

-- A standard game window (ButtonFrameTemplate): title bar, close button, rock background.
-- opts.portrait = texture shows it in the portrait circle (otherwise there's none);
-- opts.inset = false hides the inset panel. Movable by dragging; Esc closes it.
function Widgets.NativeWindow(name, title, width, height, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
	f:SetSize(width, height)
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
	if opts.portrait then
		local container = child(f, "PortraitContainer")
		local portrait = container and child(container, "portrait")
		if portrait then portrait:SetTexture(opts.portrait) end
	elseif ButtonFrameTemplate_HidePortrait then
		ButtonFrameTemplate_HidePortrait(f)
	end
	local inset = child(f, "Inset")
	if opts.inset == false and inset then inset:Hide() end
	Widgets.SetTitle(f, title)
	f:Hide()
	table.insert(UISpecialFrames, name) -- Esc closes it
	return f
end

local function createPrompt()
	prompt = Widgets.NativeWindow("JestPrompt", "", 320, 132, { inset = false })
	prompt:SetPoint("CENTER", 0, 120)
	prompt:SetFrameStrata("FULLSCREEN_DIALOG")

	prompt.box = Widgets.Input(prompt, 260)
	prompt.box:SetPoint("TOP", 2, -42)
	prompt.error = prompt:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	prompt.error:SetPoint("TOP", prompt.box, "BOTTOM", 0, -6)
	prompt.error:SetWidth(270)

	local ok = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
	ok:SetSize(90, 22)
	ok:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -4, 16)
	ok:SetText("OK")
	local cancel = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
	cancel:SetSize(90, 22)
	cancel:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 4, 16)
	cancel:SetText("Cancel")
	prompt.okButton = ok

	local function accept()
		local message = prompt.onAccept and prompt.onAccept(prompt.box:GetText())
		if message then
			prompt.error:SetText(message)
		else
			prompt:Hide()
		end
	end
	ok:SetScript("OnClick", accept)
	prompt.box:SetScript("OnEnterPressed", accept)
	cancel:SetScript("OnClick", function() prompt:Hide() end)
	prompt.box:SetScript("OnEscapePressed", function() prompt:Hide() end)
	prompt:SetScript("OnHide", function()
		prompt.onAccept = nil
		prompt.box:ClearFocus()
	end)
end

function Widgets.Prompt(title, text, onAccept)
	if not prompt then createPrompt() end
	Widgets.SetTitle(prompt, title)
	prompt.error:SetText("")
	prompt.onAccept = onAccept
	prompt.box:SetText(text or "")
	prompt:Show()
	prompt:Raise()
	prompt.box:SetFocus()
	prompt.box:HighlightText()
end

function Widgets.ClosePrompt()
	if prompt then prompt:Hide() end
end

-- The frame the open menu belongs to (nil when closed).
function Widgets.MenuAnchor()
	return menu and menu:IsShown() and menu.anchor or nil
end
