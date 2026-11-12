-- Options panel in Blizzard's Settings UI (Options -> AddOns -> Jest):
--   * "Jest" canvas page: key bindings + slice editor (list, kind, action, label, icon, test)
--   * "Appearance" vertical-layout subpage: radius, dead zone, scale, sounds
-- Everything writes to the DB and calls ns.Changed(), which re-applies the secure wheel
-- (queued until combat ends if needed).
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local ROW_H = 26
local LIST_W = 210
local KINDS = { "emote", "text", "macro" }
local KIND_LABEL = { emote = "Emote", text = "Text", macro = "Macro" }
local KIND_HINT = {
	emote = "An emote name or command, e.g. wave, dance, /roar. /jest emotes lists them all.",
	text = "Custom emote text. Others see \"<your name> <text>\".",
	macro = "Any macro text, e.g. /cast or /use. Works in combat. Up to 255 characters.",
}
local BIND_WHEEL = "CLICK JestWheelButton:LeftButton"
local BIND_REPEAT = "CLICK JestWheelButton:repeat"

local canvas = CreateFrame("Frame")
canvas:Hide()
local category
local built = false
local ui = {}
local rows = {}
Panel._ui = ui -- exposed for tests/debugging (/dump)
local selected = 1
-- Unsaved edits for the selected slice. `values` holds one draft per kind, so flicking between
-- Emote/Text/Macro never loses what was typed (or what is saved). `slice` is the saved table the
-- draft belongs to; "unsaved" is derived by comparing against it, never tracked as a flag.
local draft = { slice = nil, kind = "emote", values = {} }

local function slices()
	return ns.DB.Wheel().slices
end

local function setStatus(text, isError)
	if not ui.status then return end
	ui.status:SetText(text or "")
	if isError then
		ui.status:SetTextColor(1, 0.35, 0.35)
	else
		ui.status:SetTextColor(0.5, 1, 0.5)
	end
end

local function savedMessage()
	return InCombatLockdown() and "Saved. Applies when combat ends." or "Saved."
end

local function tooltip(owner, title, text)
	owner:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function button(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 80, 22)
	b:SetText(text)
	return b
end

local function label(parent, text, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
	fs:SetText(text)
	fs:SetJustifyH("LEFT")
	return fs
end

---------------------------------------------------------------------------
-- Key binding capture buttons
---------------------------------------------------------------------------
local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function keyText(key)
	return (GetBindingText and GetBindingText(key)) or key
end

local function modifierPrefix()
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
end

local function clearBinding(command)
	local k1, k2 = GetBindingKey(command)
	if k1 then SetBinding(k1) end
	if k2 then SetBinding(k2) end
end

local function createBindButton(parent, command)
	local b = button(parent, "", 160)
	b:RegisterForClicks("AnyUp")

	function b:Refresh()
		local key = GetBindingKey(command)
		self:SetText(key and keyText(key) or "|cff888888Not bound|r")
	end

	local function stop(self)
		self.capturing = false
		self:EnableKeyboard(false)
		self:UnlockHighlight()
		self:Refresh()
	end

	local function assign(self, key)
		stop(self)
		if InCombatLockdown() then
			setStatus("Key bindings can't be changed in combat.", true)
			return
		end
		local previous = GetBindingAction(key)
		clearBinding(command)
		if not SetBinding(key, command) then
			setStatus("Couldn't bind " .. keyText(key) .. ".", true)
			self:Refresh()
			return
		end
		SaveBindings(GetCurrentBindingSet())
		self:Refresh()
		if previous and previous ~= "" and previous ~= command then
			local name = _G["BINDING_NAME_" .. previous] or previous
			setStatus(("Bound %s. It was bound to \"%s\" before."):format(keyText(key), name))
		else
			setStatus("Bound " .. keyText(key) .. ".")
		end
	end

	b:SetScript("OnClick", function(self, mouseButton)
		if self.capturing then
			local key = MOUSE_KEYS[mouseButton]
			if key then
				assign(self, modifierPrefix() .. key)
			else
				stop(self)
			end
			return
		end
		if InCombatLockdown() then
			setStatus("Key bindings can't be changed in combat.", true)
			return
		end
		if mouseButton == "RightButton" then
			clearBinding(command)
			SaveBindings(GetCurrentBindingSet())
			self:Refresh()
			setStatus("Key cleared.")
			return
		end
		self.capturing = true
		self:LockHighlight()
		self:SetText("Press a key...")
		self:EnableKeyboard(true)
	end)

	b:SetScript("OnKeyDown", function(self, key)
		if not self.capturing or MODIFIER_KEYS[key] then return end
		if key == "ESCAPE" then
			stop(self)
			return
		end
		assign(self, modifierPrefix() .. key)
	end)

	b:SetScript("OnHide", function(self)
		if self.capturing then stop(self) end
	end)

	tooltip(b, "Key binding", "Click, then press a key (modifiers and middle/side mouse buttons work). Right-click to clear. Esc cancels.")
	return b
end

---------------------------------------------------------------------------
-- Slice list
---------------------------------------------------------------------------
local function createRow(i)
	local r = CreateFrame("Button", nil, ui.list)
	r:SetSize(LIST_W, ROW_H - 2)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, 0.04)
	r.sel = r:CreateTexture(nil, "BORDER")
	r.sel:SetAllPoints()
	r.sel:SetColorTexture(1, 0.82, 0, 0.2)
	r.sel:Hide()
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	r.num = label(r, "", "GameFontDisableSmall")
	r.num:SetPoint("LEFT", 6, 0)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(20, 20)
	r.icon:SetPoint("LEFT", 22, 0)
	r.text = label(r, "", "GameFontHighlight")
	r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.text:SetPoint("RIGHT", -4, 0)
	r.text:SetWordWrap(false)

	r:SetScript("OnClick", function() Panel.Select(i) end)
	rows[i] = r
	return r
end

---------------------------------------------------------------------------
-- Editor
---------------------------------------------------------------------------
local function draftValue()
	return draft.values[draft.kind] or ""
end

local function isDirty()
	local s = draft.slice
	if not s then return false end
	return draft.kind ~= s.kind or draftValue() ~= (s.value or "")
end

local function loadDraft()
	local s = slices()[selected]
	draft.slice = s
	draft.kind = s and s.kind or "emote"
	draft.values = {}
	if s then draft.values[s.kind] = s.value or "" end
end

-- Best-effort translation of an action into another kind ("" when there's no sensible one).
local function convert(fromKind, v, toKind)
	if v == "" or fromKind == toKind then return v end
	if toKind == "macro" then
		if fromKind == "emote" then
			local token = ns.Emotes.Resolve(v)
			return token and ("/" .. token:lower()) or ""
		end
		return "/e " .. v -- from text
	elseif toKind == "text" then
		return fromKind == "macro" and (v:match("^/e%s+(.*)$") or v:match("^/emote%s+(.*)$")) or ""
	elseif toKind == "emote" then
		local cmd = fromKind == "macro" and v:match("^(/%S+)%s*$")
		return (cmd and ns.Emotes.Resolve(cmd)) or ""
	end
	return ""
end

-- Switch the draft's kind. A kind visited before keeps its own text; otherwise seed it from the
-- current draft, falling back to the saved slice.
local function switchKind(newKind)
	if newKind == draft.kind then return end
	if draft.values[newKind] == nil then
		local seeded = convert(draft.kind, draftValue(), newKind)
		local s = draft.slice
		if seeded == "" and s and s.kind ~= draft.kind then
			seeded = convert(s.kind, s.value or "", newKind)
		end
		draft.values[newKind] = seeded
	end
	draft.kind = newKind
end

local function setDraftValue(v)
	draft.values[draft.kind] = v
	ui.save:SetEnabled(isDirty())
	ui.editorTitle:SetText(("Slice %d%s"):format(selected, isDirty() and " |cffffd100(unsaved)|r" or ""))
end

local function updateEditor()
	local s = slices()[selected]
	if not s then return end
	local dirty = isDirty()
	ui.editorTitle:SetText(("Slice %d%s"):format(selected, dirty and " |cffffd100(unsaved)|r" or ""))

	for _, kind in ipairs(KINDS) do
		if kind == draft.kind then
			ui.kind[kind]:LockHighlight()
		else
			ui.kind[kind]:UnlockHighlight()
		end
	end

	local value = draftValue()
	local isMacro = draft.kind == "macro"
	ui.single:SetShown(not isMacro)
	ui.multi:SetShown(isMacro)
	local box = isMacro and ui.multiBox or ui.single
	if box:GetText() ~= value then
		box:SetText(value)
	end

	local hint = KIND_HINT[draft.kind]
	if draft.kind ~= s.kind and ns.Slices.HasAction(s) then
		hint = ("Saved as %s: %s. Save to replace it, or switch back to keep it.\n%s"):format(
			KIND_LABEL[s.kind], ns.Slices.Label({ kind = s.kind, value = s.value }), hint)
	end
	ui.hint:SetText(hint)
	ui.counter:SetText(isMacro and ("%d/%d"):format(#value, ns.Slices.MACRO_MAX) or "")

	ui.labelBox:SetText(s.label or "")
	ui.labelHint:SetText(("Empty uses \"%s\""):format(ns.Slices.Label({ kind = s.kind, value = s.value })))
	ui.iconButton.icon:SetTexture(ns.Slices.Icon(s))
	ui.iconReset:SetEnabled(s.icon ~= nil)
	ui.test:SetEnabled(ns.Slices.IsChat(s) and ns.Slices.HasAction(s))
	ui.save:SetEnabled(dirty)
	ui.revert:SetEnabled(dirty)
end

function Panel.Save()
	local s = slices()[selected]
	if not s then return false end
	local value, err = ns.Slices.Validate(draft.kind, draftValue())
	if not value then
		setStatus(err, true)
		return false
	end
	s.kind, s.value = draft.kind, value
	loadDraft()
	ns.Changed() -- triggers Panel.Refresh via the change listener
	setStatus(savedMessage())
	return true
end

-- Leaving a slice with unsaved edits: keep them if valid, otherwise say they were dropped.
local function settleDraft()
	if not isDirty() then return end
	if not Panel.Save() then
		setStatus(("Unsaved changes to slice %d were discarded (%s)"):format(selected, ui.status:GetText()), true)
		loadDraft()
	end
end

local function commitLabel()
	local s = slices()[selected]
	if not s then return end
	local text = ui.labelBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
	local newLabel = text ~= "" and text or nil
	if newLabel ~= s.label then
		s.label = newLabel
		ns.Changed()
		setStatus(savedMessage())
	end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function build()
	built = true

	local title = label(canvas, "Jest", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	local sub = label(canvas, "Hold your wheel key, aim at a slice and release. Release in the centre or press Esc to cancel.", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	-- Bindings row
	local wheelLabel = label(canvas, "Wheel key")
	wheelLabel:SetPoint("TOPLEFT", 16, -72)
	ui.bindWheel = createBindButton(canvas, BIND_WHEEL)
	ui.bindWheel:SetPoint("LEFT", wheelLabel, "RIGHT", 10, 0)
	local repeatLabel = label(canvas, "Repeat key")
	repeatLabel:SetPoint("LEFT", ui.bindWheel, "RIGHT", 24, 0)
	ui.bindRepeat = createBindButton(canvas, BIND_REPEAT)
	ui.bindRepeat:SetPoint("LEFT", repeatLabel, "RIGHT", 10, 0)

	-- Slice list
	local listTitle = label(canvas, "Slices (clockwise from the top)")
	listTitle:SetPoint("TOPLEFT", 16, -112)
	ui.list = CreateFrame("Frame", nil, canvas)
	ui.list:SetSize(LIST_W, ROW_H * ns.MAX_SLICES)
	ui.list:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 0, -6)
	for i = 1, ns.MAX_SLICES do
		createRow(i)
	end

	ui.add = button(canvas, "Add", 50)
	ui.add:SetPoint("TOPLEFT", ui.list, "BOTTOMLEFT", 0, -6)
	ui.remove = button(canvas, "Remove", 66)
	ui.remove:SetPoint("LEFT", ui.add, "RIGHT", 4, 0)
	ui.up = button(canvas, "Up", 42)
	ui.up:SetPoint("LEFT", ui.remove, "RIGHT", 4, 0)
	ui.down = button(canvas, "Down", 42)
	ui.down:SetPoint("LEFT", ui.up, "RIGHT", 4, 0)

	ui.add:SetScript("OnClick", function()
		local list = slices()
		if #list >= ns.MAX_SLICES then
			setStatus(("The wheel holds at most %d slices."):format(ns.MAX_SLICES), true)
			return
		end
		settleDraft()
		table.insert(list, { kind = "emote", value = "" })
		selected = #list
		ns.Changed()
		ui.single:SetFocus()
	end)
	ui.remove:SetScript("OnClick", function()
		local list = slices()
		if #list <= 1 then
			setStatus("The wheel needs at least one slice.", true)
			return
		end
		table.remove(list, selected)
		selected = math.min(selected, #list)
		ns.Changed() -- Refresh sees the draft belongs to a removed slice and reloads it
	end)
	local function move(delta)
		local list = slices()
		local target = selected + delta
		if target < 1 or target > #list then return end
		settleDraft()
		list[selected], list[target] = list[target], list[selected]
		selected = target
		ns.Changed()
	end
	ui.up:SetScript("OnClick", function() move(-1) end)
	ui.down:SetScript("OnClick", function() move(1) end)

	-- Editor
	local ex = 16 + LIST_W + 28
	ui.editorTitle = label(canvas, "", "GameFontNormalLarge")
	ui.editorTitle:SetPoint("TOPLEFT", ex, -112)

	local kindLabel = label(canvas, "Type", "GameFontHighlightSmall")
	kindLabel:SetPoint("TOPLEFT", ui.editorTitle, "BOTTOMLEFT", 0, -14)
	ui.kind = {}
	local prevKind
	for _, kind in ipairs(KINDS) do
		local b = button(canvas, KIND_LABEL[kind], 80)
		if prevKind then
			b:SetPoint("LEFT", prevKind, "RIGHT", 4, 0)
		else
			b:SetPoint("LEFT", kindLabel, "RIGHT", 46, 0)
		end
		b:SetScript("OnClick", function()
			switchKind(kind)
			updateEditor()
		end)
		ui.kind[kind] = b
		prevKind = b
	end

	local actionLabel = label(canvas, "Action", "GameFontHighlightSmall")
	actionLabel:SetPoint("TOPLEFT", kindLabel, "BOTTOMLEFT", 0, -22)

	-- Single-line box for emote/text.
	ui.single = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
	ui.single:SetSize(300, 20)
	ui.single:SetPoint("LEFT", actionLabel, "RIGHT", 52, 0)
	ui.single:SetAutoFocus(false)
	ui.single:SetMaxLetters(255)
	ui.single:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			setDraftValue(self:GetText())
		end
	end)
	ui.single:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		Panel.Save()
	end)

	-- Multi-line box for macros.
	ui.multi = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
	ui.multi:SetSize(300, 84)
	ui.multi:SetPoint("TOPLEFT", ui.single, "TOPLEFT", -6, 4)
	ui.multi:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	ui.multi:SetBackdropColor(0, 0, 0, 0.5)
	ui.multi:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	ui.multi:EnableMouse(true)
	ui.multiBox = CreateFrame("EditBox", nil, ui.multi)
	ui.multiBox:SetMultiLine(true)
	ui.multiBox:SetAutoFocus(false)
	ui.multiBox:SetFontObject(ChatFontNormal)
	ui.multiBox:SetMaxLetters(ns.Slices.MACRO_MAX)
	ui.multiBox:SetPoint("TOPLEFT", 6, -6)
	ui.multiBox:SetPoint("BOTTOMRIGHT", -6, 6)
	ui.multi:SetScript("OnMouseDown", function() ui.multiBox:SetFocus() end)
	ui.multiBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	ui.multiBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			setDraftValue(self:GetText())
			ui.counter:SetText(("%d/%d"):format(#draftValue(), ns.Slices.MACRO_MAX))
		end
	end)

	ui.hint = label(canvas, "", "GameFontDisableSmall")
	ui.hint:SetPoint("TOPLEFT", ui.multi, "BOTTOMLEFT", 6, -4)
	ui.hint:SetWidth(300)
	ui.counter = label(canvas, "", "GameFontDisableSmall")
	ui.counter:SetPoint("TOPRIGHT", ui.multi, "BOTTOMRIGHT", 0, -4)

	ui.save = button(canvas, "Save", 80)
	ui.save:SetPoint("TOPLEFT", ui.multi, "BOTTOMLEFT", 0, -40) -- room for a two-line hint
	ui.save:SetScript("OnClick", function() Panel.Save() end)
	ui.revert = button(canvas, "Revert", 80)
	ui.revert:SetPoint("LEFT", ui.save, "RIGHT", 4, 0)
	ui.revert:SetScript("OnClick", function()
		loadDraft()
		updateEditor()
		setStatus("")
	end)
	ui.test = button(canvas, "Test", 80)
	ui.test:SetPoint("LEFT", ui.revert, "RIGHT", 4, 0)
	ui.test:SetScript("OnClick", function()
		if isDirty() then
			setStatus("Save first, then test.", true)
		elseif not ns.SecureWheel.TestChat(selected) then
			setStatus("Only emote and text slices can be tested here; macros fire from the wheel.", true)
		end
	end)
	tooltip(ui.test, "Test", "Performs this emote/text slice now. Macro slices can only fire from the wheel.")

	-- Label
	local labelLabel = label(canvas, "Label", "GameFontHighlightSmall")
	labelLabel:SetPoint("TOPLEFT", ui.save, "BOTTOMLEFT", 0, -22)
	ui.labelBox = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
	ui.labelBox:SetSize(200, 20)
	ui.labelBox:SetPoint("LEFT", labelLabel, "RIGHT", 56, 0)
	ui.labelBox:SetAutoFocus(false)
	ui.labelBox:SetMaxLetters(40)
	ui.labelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	ui.labelBox:SetScript("OnEditFocusLost", commitLabel)
	ui.labelHint = label(canvas, "", "GameFontDisableSmall")
	ui.labelHint:SetPoint("TOPLEFT", ui.labelBox, "BOTTOMLEFT", -4, -2)

	-- Icon
	local iconLabel = label(canvas, "Icon", "GameFontHighlightSmall")
	iconLabel:SetPoint("TOPLEFT", labelLabel, "BOTTOMLEFT", 0, -40)
	ui.iconButton = CreateFrame("Button", nil, canvas)
	ui.iconButton:SetSize(44, 44)
	ui.iconButton:SetPoint("TOPLEFT", iconLabel, "TOPRIGHT", 62, 8)
	ui.iconButton.icon = ui.iconButton:CreateTexture(nil, "ARTWORK")
	ui.iconButton.icon:SetAllPoints()
	ui.iconButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tooltip(ui.iconButton, "Change icon")
	ui.iconButton:SetScript("OnClick", function(self)
		local s = slices()[selected]
		ns.IconPicker.Open(self, ns.Slices.Icon(s), function(icon)
			local target = slices()[selected]
			if target then
				target.icon = icon
				ns.Changed()
				setStatus(savedMessage())
			end
		end)
	end)
	ui.iconReset = button(canvas, "Default icon", 100)
	ui.iconReset:SetPoint("LEFT", ui.iconButton, "RIGHT", 10, 0)
	ui.iconReset:SetScript("OnClick", function()
		local s = slices()[selected]
		if s then
			s.icon = nil
			ns.Changed()
			setStatus(savedMessage())
		end
	end)

	-- Status line
	ui.status = label(canvas, "", "GameFontHighlightSmall")
	ui.status:SetPoint("TOPLEFT", ui.add, "BOTTOMLEFT", 0, -12)
	ui.status:SetPoint("RIGHT", canvas, "RIGHT", -16, 0)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function Panel.Refresh()
	if not built then return end
	local list = slices()
	selected = math.max(1, math.min(selected, #list))
	for i, r in ipairs(rows) do
		local s = list[i]
		if s then
			r.num:SetText(ns.Slices.KeyLabel(i))
			r.icon:SetTexture(ns.Slices.Icon(s))
			r.icon:SetDesaturated(not ns.Slices.HasAction(s))
			r.text:SetText(ns.Slices.HasAction(s) and ns.Slices.Label(s) or "|cff888888(empty)|r")
			r.sel:SetShown(i == selected)
			r:Show()
		else
			r:Hide()
		end
	end
	ui.add:SetEnabled(#list < ns.MAX_SLICES)
	ui.remove:SetEnabled(#list > 1)
	ui.up:SetEnabled(selected > 1)
	ui.down:SetEnabled(selected < #list)
	ui.bindWheel:Refresh()
	ui.bindRepeat:Refresh()
	-- Reload the draft unless it holds unsaved edits for the slice still selected.
	if draft.slice ~= list[selected] or not isDirty() then loadDraft() end
	updateEditor()
end

function Panel.Select(i)
	if i == selected then return end
	settleDraft()
	selected = i
	loadDraft()
	Panel.Refresh()
end

canvas:SetScript("OnShow", function()
	if not built then build() end
	Panel.Refresh()
end)
canvas:SetScript("OnHide", function()
	settleDraft()
	ns.IconPicker.Close()
end)

-- Hooks the Settings panel may call on canvas pages.
canvas.OnCommit = function() end
canvas.OnDefault = function() end
canvas.OnRefresh = function() Panel.Refresh() end

ns.OnChanged(function()
	if canvas:IsShown() then Panel.Refresh() end
end)

local function registerAppearance(parent)
	local sub = Settings.RegisterVerticalLayoutSubcategory(parent, "Appearance")
	local varType = Settings.VarType or {}

	local function slider(key, name, minV, maxV, step, fmt, tooltipText, round)
		local setting = Settings.RegisterProxySetting(sub, "JEST_" .. key:upper(), varType.Number or "number", name,
			ns.Defaults.profile[key],
			function() return ns.DB.Profile()[key] end,
			function(v)
				ns.DB.Profile()[key] = round(v)
				ns.Changed()
			end)
		local options = Settings.CreateSliderOptions(minV, maxV, step)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
		end
		Settings.CreateSlider(sub, setting, options, tooltipText)
	end

	local function whole(v) return math.floor(v + 0.5) end
	local function twentieths(v) return math.floor(v * 20 + 0.5) / 20 end

	slider("radius", "Ring radius", 40, 300, 1, function(v) return ("%d"):format(v) end,
		"Distance from the centre of the wheel to the slice icons.", whole)
	slider("deadZone", "Cancel zone", 8, 100, 1, function(v) return ("%d"):format(v) end,
		"Releasing the key within this distance of the centre cancels.", whole)
	slider("scale", "Wheel scale", 0.5, 2, 0.05, function(v) return ("%.2f"):format(v) end,
		"Overall size of the wheel.", twentieths)

	local sounds = Settings.RegisterProxySetting(sub, "JEST_SOUNDS", varType.Boolean or "boolean", "Sounds",
		ns.Defaults.profile.sounds,
		function() return ns.DB.Profile().sounds end,
		function(v) ns.DB.Profile().sounds = v end)
	Settings.CreateCheckbox(sub, sounds, "Play sounds when hovering, firing and cancelling.")
end

function Panel.Register()
	if category then return end
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		ns.Debug("Settings API unavailable; use /jest help")
		return
	end
	category = Settings.RegisterCanvasLayoutCategory(canvas, "Jest")
	local ok, err = pcall(registerAppearance, category)
	if not ok then
		ns.Debug("Appearance page failed:", err)
	end
	Settings.RegisterAddOnCategory(category)
end

function Panel.Open()
	if not category then
		ns.Print("The options panel is unavailable; use /jest help.")
		return
	end
	local id = category.GetID and category:GetID() or category.ID
	Settings.OpenToCategory(id)
end
