-- Small shared UI widgets for the options panel and icon picker.
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

-- Single-line text input.
-- Deliberately NOT built on InputBoxTemplate: on WoW: Forever, Backspace does nothing in boxes
-- created from that template (it pulls in NarrationEditBoxMixin; exact cause unconfirmed), while
-- plain EditBoxes behave normally.
-- Callers that need focus-lost behaviour should use HookScript("OnEditFocusLost", ...) so the
-- focus styling below is kept.
function Widgets.Input(parent, width, maxLetters)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width, 22)
	box:SetBackdrop(BACKDROP)
	box:SetBackdropColor(0, 0, 0, 0.5)
	setBorder(box, BORDER)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(6, 6, 0, 0)
	box:SetAutoFocus(false)
	if maxLetters then
		box:SetMaxLetters(maxLetters)
	end
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self)
		setBorder(self, BORDER_FOCUS)
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		setBorder(self, BORDER)
		self:HighlightText(0, 0)
	end)
	Widgets.TraceInput(box)
	return box
end

-- Grey hint text shown inside an input while it's empty.
function Widgets.SetPlaceholder(box, text)
	if not box.placeholder then
		local fs = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
		fs:SetPoint("LEFT", 6, 0)
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

-- Segmented control: a row of mutually exclusive options.
-- items = { { value = "emote", text = "Emote" }, ... }; onSelect(value) is called on click.
-- Returns the holder; holder.buttons[value] are the clickable segments; holder:SetValue(v).
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

-- Small coloured tag ("pill") with a label.
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

-- What an emote does besides its chat line: "Anim" and/or "Voice" tags in fixed columns (so
-- they line up down a list), or a grey "Text only" tag when it does neither.
-- holder:SetEmote(token); nothing is shown for emotes missing from the data.
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

-- Toggleable chip styled like the tags: dim outline when off, filled in its colour when on.
-- onChange(checked) is called on click; chip:SetChecked(bool) updates it without calling back.
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

-- One-line key for the tags, using the same colours.
function Widgets.EmoteBadgeLegend()
	local function hex(c)
		return ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
	end
	return ("|cff%sAnim|r animation   |cff%sVoice|r spoken line"):format(hex(Widgets.ANIM_COLOR), hex(Widgets.VOICE_COLOR))
end

-- /jest debug: log every text change so input problems can be diagnosed from chat.
-- Callers must use HookScript (not SetScript) for OnTextChanged or this trace is lost.
function Widgets.TraceInput(box, name)
	if name then box.debugName = name end
	box:HookScript("OnTextChanged", function(self, userInput)
		if ns.debug then
			ns.Debug(("[input %s] changed userInput=%s text=%q"):format(
				self.debugName or "?", tostring(userInput), self:GetText()))
		end
	end)
end
