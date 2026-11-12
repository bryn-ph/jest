-- Options panel in Blizzard's Settings UI (Options -> AddOns -> Jest):
--   * "Jest" canvas page: key bindings + slice list + slice editor card
--   * "Appearance" vertical-layout subpage: radius, dead zone, scale, sounds
-- Everything writes to the DB and calls ns.Changed(), which re-applies the secure wheel
-- (queued until combat ends if needed).
local addonName, ns = ...

local Panel = {}
ns.Panel = Panel

local ROW_H = 24
local LIST_W = 220
local LEFT = 16          -- canvas left padding
local FIELD_X = 70       -- x of input controls inside the editor card
local SUGGEST_MAX = 8
local SUGGEST_ROW_H = 20
local STATUS_SECONDS = 4 -- success messages clear themselves after this long

local KINDS = { "emote", "text", "macro" }
local KIND_LABEL = { emote = "Emote", text = "Text", macro = "Macro" }
local KIND_HINT = {
	emote = "Start typing to search emotes (e.g. wave, dance, roar). Tab or Enter picks the highlighted one.",
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

local statusToken = 0
local function setStatus(text, isError)
	if not ui.status then return end
	text = text or ""
	ui.status:SetText(text)
	if isError then
		ui.status:SetTextColor(1, 0.35, 0.35)
	else
		ui.status:SetTextColor(0.5, 1, 0.5)
	end
	statusToken = statusToken + 1
	local token = statusToken
	if text ~= "" and not isError and C_Timer and C_Timer.After then
		C_Timer.After(STATUS_SECONDS, function()
			if token == statusToken then ui.status:SetText("") end
		end)
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

local function addonVersion()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return get and get(addonName, "Version") or nil
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
	local b = button(parent, "", 150)
	b:RegisterForClicks("AnyUp")

	function b:Refresh()
		local key = GetBindingKey(command)
		self:SetText(key and keyText(key) or "|cff888888Not bound|r")
	end

	-- IMPORTANT: the OnKeyDown handler exists only while capturing. Setting an OnKeyDown script
	-- turns keyboard input on for the frame, and a permanently keyboard-enabled button here
	-- swallowed Backspace from the panel's text boxes.
	local onKeyDown

	local function stop(self)
		self.capturing = false
		self:SetScript("OnKeyDown", nil)
		self:EnableKeyboard(false)
		self:UnlockHighlight()
		self:Refresh()
	end

	local function start(self)
		self.capturing = true
		self:LockHighlight()
		self:SetText("Press a key...")
		self:SetScript("OnKeyDown", onKeyDown)
		self:EnableKeyboard(true)
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
		start(self)
	end)

	onKeyDown = function(self, key)
		if not self.capturing or MODIFIER_KEYS[key] then return end
		if key == "ESCAPE" then
			stop(self)
			return
		end
		assign(self, modifierPrefix() .. key)
	end
	b:EnableKeyboard(false)

	b:SetScript("OnHide", function(self)
		if self.capturing then stop(self) end
	end)

	tooltip(b, "Key binding", "Click, then press a key. Modifiers and middle/side mouse buttons work. Right-click to clear; Esc cancels.")
	return b
end

---------------------------------------------------------------------------
-- Slice list
---------------------------------------------------------------------------
local function rowTooltip(r)
	local s = slices()[r.index]
	if not s then return end
	GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.Slices.HasAction(s) and ns.Slices.Label(s) or "Empty slice", 1, 1, 1)
	if ns.Slices.HasAction(s) then
		GameTooltip:AddLine(KIND_LABEL[s.kind] .. ": " .. s.value, 0.8, 0.8, 0.8, true)
	end
	local key = ns.Slices.KeyLabel(r.index)
	if key ~= "" then
		GameTooltip:AddLine("Press " .. key .. " while the wheel is open to fire it.", 0.5, 0.5, 0.5, true)
	end
	GameTooltip:Show()
end

local function createRow(i)
	local r = CreateFrame("Button", nil, ui.list)
	r.index = i
	r:SetSize(LIST_W, ROW_H - 2)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, 0.04)
	r.sel = r:CreateTexture(nil, "BORDER")
	r.sel:SetAllPoints()
	r.sel:SetColorTexture(1, 0.82, 0, 0.2)
	r.sel:Hide()
	r.selBar = r:CreateTexture(nil, "ARTWORK")
	r.selBar:SetColorTexture(1, 0.82, 0, 0.9)
	r.selBar:SetWidth(2)
	r.selBar:SetPoint("TOPLEFT")
	r.selBar:SetPoint("BOTTOMLEFT")
	r.selBar:Hide()
	local hover = r:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.07)

	r.num = label(r, "", "GameFontDisableSmall")
	r.num:SetPoint("LEFT", 8, 0)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT", 22, 0)
	ns.CropIcon(r.icon)
	r.kind = label(r, "", "GameFontDisableSmall")
	r.kind:SetPoint("RIGHT", -8, 0)
	r.text = label(r, "", "GameFontHighlight")
	r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
	r.text:SetPoint("RIGHT", r.kind, "LEFT", -6, 0)
	r.text:SetWordWrap(false)

	r:SetScript("OnClick", function() Panel.Select(i) end)
	r:SetScript("OnEnter", rowTooltip)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = r
	return r
end

---------------------------------------------------------------------------
-- Drafts
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

local function updateDirtyState()
	local dirty = isDirty()
	ui.unsaved:SetShown(dirty)
	ui.save:SetEnabled(dirty)
	ui.revert:SetEnabled(dirty)
end

local function setDraftValue(v)
	draft.values[draft.kind] = v
	updateDirtyState()
end

---------------------------------------------------------------------------
-- Emote suggestions (dropdown under the action box while typing an emote)
---------------------------------------------------------------------------
local suggestIndex = 0

local function hideSuggestions()
	if ui.suggest then ui.suggest:Hide() end
	suggestIndex = 0
end

local function highlightSuggestion(i)
	suggestIndex = i
	for k, row in ipairs(ui.suggest.rows) do
		row.sel:SetShown(k == i)
	end
end

local function updateSuggestions()
	if draft.kind ~= "emote" or not ui.single:HasFocus() then
		hideSuggestions()
		return
	end
	local text = ui.single:GetText()
	local matches = ns.Emotes.Search(text, SUGGEST_MAX)
	local exact = ns.Emotes.Resolve(text)
	if #matches == 0 or (#matches == 1 and matches[1].token == exact) then
		hideSuggestions()
		return
	end
	for k, row in ipairs(ui.suggest.rows) do
		local e = matches[k]
		if e then
			row.token = e.token
			row.text:SetText(ns.Emotes.Label(e.token))
			row.cmd:SetText(e.cmd or e.token)
			row:Show()
		else
			row:Hide()
		end
	end
	ui.suggest:SetHeight(#matches * SUGGEST_ROW_H + 2)
	ui.suggest:Show()
	highlightSuggestion(1)
end

local function moveSuggestion(delta)
	if not ui.suggest:IsShown() then return end
	local count = 0
	for _, row in ipairs(ui.suggest.rows) do
		if row:IsShown() then count = count + 1 end
	end
	if count == 0 then return end
	highlightSuggestion((suggestIndex - 1 + delta) % count + 1)
end

---------------------------------------------------------------------------
-- Editor
---------------------------------------------------------------------------
local function updateEditor()
	local s = slices()[selected]
	if not s then return end
	ui.editorTitle:SetText(("Slice %d"):format(selected))
	ui.kindSwitch:SetValue(draft.kind)

	local value = draftValue()
	local isMacro = draft.kind == "macro"
	ui.single:SetShown(not isMacro)
	ui.multi:SetShown(isMacro)
	local box = isMacro and ui.multiBox or ui.single
	if box:GetText() ~= value then
		ns.Debug(("[panel] updateEditor rewrites %s: %q -> %q"):format(box.debugName or "?", box:GetText(), value))
		box:SetText(value)
	end
	if not isMacro then hideSuggestions() end

	-- The hint (and everything below it) follows whichever action box is visible.
	ui.hint:ClearAllPoints()
	ui.hint:SetPoint("TOPLEFT", isMacro and ui.multi or ui.single, "BOTTOMLEFT", 0, -6)
	ui.hint:SetPoint("RIGHT", ui.card, "RIGHT", -12, 0)
	local hint = KIND_HINT[draft.kind]
	if draft.kind ~= s.kind and ns.Slices.HasAction(s) then
		hint = ("|cffffd100Saved as %s: %s.|r Save to replace it, or switch back to keep it.\n%s"):format(
			KIND_LABEL[s.kind], ns.Slices.Label({ kind = s.kind, value = s.value }), hint)
	end
	ui.hint:SetText(hint)
	ui.counter:SetText(isMacro and ("%d/%d"):format(#value, ns.Slices.MACRO_MAX) or "")

	if ui.labelBox:GetText() ~= (s.label or "") then
		ns.Debug(("[panel] updateEditor rewrites label: %q -> %q"):format(ui.labelBox:GetText(), s.label or ""))
		ui.labelBox:SetText(s.label or "")
	end
	ns.Widgets.SetPlaceholder(ui.labelBox, ns.Slices.Label({ kind = s.kind, value = s.value }))
	ui.iconButton.icon:SetTexture(ns.Slices.Icon(s))
	ui.iconReset:SetEnabled(s.icon ~= nil)
	ui.test:SetEnabled(ns.Slices.IsChat(s) and ns.Slices.HasAction(s))
	updateDirtyState()
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

local function pickSuggestion(token)
	hideSuggestions()
	draft.values.emote = token
	ui.single:SetText(token)
	ui.single:ClearFocus()
	Panel.Save()
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
local function buildHeader()
	local title = label(canvas, "Jest", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", LEFT, -16)
	local version = addonVersion()
	if version then
		local v = label(canvas, "v" .. version, "GameFontDisableSmall")
		v:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 2)
	end
	local sub = label(canvas, "Hold your wheel key, aim at a slice and release. Release in the centre or press Esc to cancel. Type /jest help for chat commands.", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetPoint("RIGHT", canvas, "RIGHT", -LEFT, 0)
end

local function buildBindings()
	local header = ns.Widgets.Header(canvas, "Key bindings")
	header:SetPoint("TOPLEFT", LEFT, -84)

	local wheelLabel = label(canvas, "Open wheel", "GameFontHighlight")
	wheelLabel:SetPoint("TOPLEFT", LEFT, -112)
	ui.bindWheel = createBindButton(canvas, BIND_WHEEL)
	ui.bindWheel:SetPoint("LEFT", wheelLabel, "RIGHT", 10, 0)
	local repeatLabel = label(canvas, "Repeat last", "GameFontHighlight")
	repeatLabel:SetPoint("LEFT", ui.bindWheel, "RIGHT", 28, 0)
	ui.bindRepeat = createBindButton(canvas, BIND_REPEAT)
	ui.bindRepeat:SetPoint("LEFT", repeatLabel, "RIGHT", 10, 0)

	local hint = label(canvas, "Click a button, then press a key. Right-click a button to clear it.", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", wheelLabel, "BOTTOMLEFT", 0, -12)
end

local function buildList()
	local header = ns.Widgets.Header(canvas, "Slices  |cff888888clockwise from the top|r")
	header:SetPoint("TOPLEFT", LEFT, -168)

	-- Toolbar above the list so it never moves as slices are added/removed.
	ui.add = button(canvas, "Add", 54)
	ui.add:SetPoint("TOPLEFT", LEFT, -190)
	ui.remove = button(canvas, "Remove", 70)
	ui.remove:SetPoint("LEFT", ui.add, "RIGHT", 4, 0)
	ui.up = button(canvas, "Up", 44)
	ui.up:SetPoint("LEFT", ui.remove, "RIGHT", 4, 0)
	ui.down = button(canvas, "Down", 44)
	ui.down:SetPoint("LEFT", ui.up, "RIGHT", 4, 0)
	tooltip(ui.up, "Move up", "Moves the slice one step anticlockwise on the wheel.")
	tooltip(ui.down, "Move down", "Moves the slice one step clockwise on the wheel.")

	ui.list = CreateFrame("Frame", nil, canvas)
	ui.list:SetSize(LIST_W, ROW_H * ns.MAX_SLICES)
	ui.list:SetPoint("TOPLEFT", ui.add, "BOTTOMLEFT", 0, -8)
	for i = 1, ns.MAX_SLICES do
		createRow(i)
	end

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
		setStatus("Slice removed.")
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
end

local function buildSuggestions()
	local f = CreateFrame("Frame", nil, ui.card, "BackdropTemplate")
	f:SetFrameLevel((ui.card:GetFrameLevel() or 0) + 20)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
	f:SetBackdropBorderColor(1, 0.82, 0, 0.6)
	f:SetPoint("TOPLEFT", ui.single, "BOTTOMLEFT", 0, -2)
	f:SetPoint("TOPRIGHT", ui.single, "BOTTOMRIGHT", 0, -2)
	f.rows = {}
	for i = 1, SUGGEST_MAX do
		local row = CreateFrame("Button", nil, f)
		row:SetHeight(SUGGEST_ROW_H)
		row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * SUGGEST_ROW_H)
		row:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * SUGGEST_ROW_H)
		row.sel = row:CreateTexture(nil, "BACKGROUND")
		row.sel:SetAllPoints()
		row.sel:SetColorTexture(1, 0.82, 0, 0.2)
		row.sel:Hide()
		local hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.08)
		row.text = label(row, "", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 8, 0)
		row.cmd = label(row, "", "GameFontDisableSmall")
		row.cmd:SetPoint("RIGHT", -8, 0)
		row:SetScript("OnClick", function(self) pickSuggestion(self.token) end)
		f.rows[i] = row
	end
	f:Hide()
	ui.suggest = f
end

local function buildEditor()
	local card = ns.Widgets.Card(canvas)
	card:SetPoint("TOPLEFT", ui.add, "TOPLEFT", LIST_W + 16, 0)
	card:SetPoint("RIGHT", canvas, "RIGHT", -LEFT, 0)
	card:SetHeight(360) -- fits the worst case: macro box + three-line hint + label/icon + status
	ui.card = card

	ui.editorTitle = label(card, "", "GameFontNormalLarge")
	ui.editorTitle:SetPoint("TOPLEFT", 12, -12)
	ui.unsaved = label(card, "Unsaved changes", "GameFontNormalSmall")
	ui.unsaved:SetPoint("TOPRIGHT", -12, -15)
	ui.unsaved:Hide()

	-- Type
	local kindLabel = label(card, "Type", "GameFontHighlightSmall")
	kindLabel:SetPoint("TOPLEFT", 12, -50)
	local items = {}
	for _, kind in ipairs(KINDS) do
		items[#items + 1] = { value = kind, text = KIND_LABEL[kind] }
	end
	ui.kindSwitch = ns.Widgets.Segmented(card, items, 222, function(kind)
		switchKind(kind)
		updateEditor()
	end)
	ui.kindSwitch:SetPoint("TOPLEFT", FIELD_X, -44)
	ui.kind = ui.kindSwitch.buttons

	-- Action
	local actionLabel = label(card, "Action", "GameFontHighlightSmall")
	actionLabel:SetPoint("TOPLEFT", 12, -86)

	ui.single = ns.Widgets.Input(card, 200, 255)
	ui.single.debugName = "action"
	ui.single:SetPoint("TOPLEFT", FIELD_X, -80)
	ui.single:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	ui.single:HookScript("OnTextChanged", function(self, userInput)
		if userInput then
			setDraftValue(self:GetText())
			updateSuggestions()
		end
	end)
	ui.single:HookScript("OnEditFocusGained", updateSuggestions)
	ui.single:HookScript("OnEditFocusLost", function()
		-- Clicking a suggestion takes focus first; keep the list until the click lands.
		if not (ui.suggest and ui.suggest:IsMouseOver()) then hideSuggestions() end
	end)
	ui.single:SetScript("OnEnterPressed", function(self)
		if ui.suggest:IsShown() and suggestIndex > 0 then
			pickSuggestion(ui.suggest.rows[suggestIndex].token)
			return
		end
		self:ClearFocus()
		Panel.Save()
	end)
	ui.single:SetScript("OnTabPressed", function()
		if ui.suggest:IsShown() and suggestIndex > 0 then
			pickSuggestion(ui.suggest.rows[suggestIndex].token)
		end
	end)
	ui.single:SetScript("OnArrowPressed", function(_, key)
		if key == "DOWN" then moveSuggestion(1) elseif key == "UP" then moveSuggestion(-1) end
	end)

	ui.multi = CreateFrame("Frame", nil, card, "BackdropTemplate")
	ui.multi:SetHeight(84)
	ui.multi:SetPoint("TOPLEFT", FIELD_X, -80)
	ui.multi:SetPoint("RIGHT", card, "RIGHT", -12, 0)
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
	ui.multiBox:SetScript("OnEditFocusGained", function() ui.multi:SetBackdropBorderColor(1, 0.82, 0, 1) end)
	ui.multiBox:SetScript("OnEditFocusLost", function() ui.multi:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end)
	ui.multiBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			setDraftValue(self:GetText())
			ui.counter:SetText(("%d/%d"):format(#draftValue(), ns.Slices.MACRO_MAX))
		end
	end)
	ns.Widgets.TraceInput(ui.multiBox, "macro")

	ui.hint = label(card, "", "GameFontDisableSmall")
	ui.hint:SetPoint("TOPLEFT", ui.single, "BOTTOMLEFT", 0, -6) -- re-anchored in updateEditor
	ui.hint:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	ui.counter = label(card, "", "GameFontDisableSmall")
	ui.counter:SetPoint("BOTTOMRIGHT", ui.multi, "TOPRIGHT", 0, 3)

	-- Actions
	ui.save = button(card, "Save", 80)
	ui.save:SetPoint("TOPLEFT", ui.hint, "BOTTOMLEFT", 0, -10)
	ui.save:SetScript("OnClick", function() Panel.Save() end)
	ui.revert = button(card, "Revert", 80)
	ui.revert:SetPoint("LEFT", ui.save, "RIGHT", 4, 0)
	ui.revert:SetScript("OnClick", function()
		loadDraft()
		updateEditor()
		setStatus("")
	end)
	ui.test = button(card, "Test", 70)
	ui.test:SetPoint("LEFT", ui.revert, "RIGHT", 4, 0)
	ui.test:SetScript("OnClick", function()
		if isDirty() then
			setStatus("Save first, then test.", true)
		elseif not ns.SecureWheel.TestChat(selected) then
			setStatus("Only emote and text slices can be tested here; macros fire from the wheel.", true)
		end
	end)
	tooltip(ui.test, "Test", "Performs this emote/text slice now. Macro slices can only fire from the wheel.")

	-- Status is pinned to the card's bottom edge so messages never shift the layout.
	ui.status = label(card, "", "GameFontHighlightSmall")
	ui.status:SetPoint("BOTTOMLEFT", 12, 10)
	ui.status:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	ui.status:SetHeight(24)
	ui.status:SetJustifyV("BOTTOM")

	-- Look: label + icon
	local divider = card:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.08)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", ui.save, "BOTTOMLEFT", -FIELD_X + 12, -10)
	divider:SetPoint("RIGHT", card, "RIGHT", -12, 0)

	local labelLabel = label(card, "Label", "GameFontHighlightSmall")
	labelLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -16)
	ui.labelBox = ns.Widgets.Input(card, 180, 40)
	ui.labelBox.debugName = "label"
	ui.labelBox:SetPoint("LEFT", labelLabel, "LEFT", FIELD_X - 12, 0)
	ui.labelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	ui.labelBox:HookScript("OnEditFocusLost", commitLabel) -- Hook keeps the widget's focus styling
	tooltip(ui.labelBox, "Label", "Name shown in the middle of the wheel. Leave empty to use the default (shown in grey).")

	local iconLabel = label(card, "Icon", "GameFontHighlightSmall")
	iconLabel:SetPoint("TOPLEFT", labelLabel, "BOTTOMLEFT", 0, -28)
	ui.iconButton = CreateFrame("Button", nil, card, "BackdropTemplate")
	ui.iconButton:SetSize(36, 36)
	ui.iconButton:SetPoint("LEFT", iconLabel, "LEFT", FIELD_X - 12, 0)
	ui.iconButton:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	ui.iconButton:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	ui.iconButton.icon = ui.iconButton:CreateTexture(nil, "ARTWORK")
	ui.iconButton.icon:SetPoint("TOPLEFT", 1, -1)
	ui.iconButton.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	ns.CropIcon(ui.iconButton.icon)
	local iconHover = ui.iconButton:CreateTexture(nil, "HIGHLIGHT")
	iconHover:SetAllPoints(ui.iconButton.icon)
	iconHover:SetColorTexture(1, 1, 1, 0.15)

	local function openPicker()
		local s = slices()[selected]
		ns.IconPicker.Open(ui.iconButton, ns.Slices.Icon(s), function(icon)
			local target = slices()[selected]
			if target then
				target.icon = icon
				ns.Changed()
				setStatus(savedMessage())
			end
		end)
	end
	ui.iconButton:SetScript("OnClick", openPicker)
	tooltip(ui.iconButton, "Change icon")
	ui.iconChoose = button(card, "Choose...", 84)
	ui.iconChoose:SetPoint("LEFT", ui.iconButton, "RIGHT", 10, 0)
	ui.iconChoose:SetScript("OnClick", openPicker)
	ui.iconReset = button(card, "Default", 70)
	ui.iconReset:SetPoint("LEFT", ui.iconChoose, "RIGHT", 4, 0)
	ui.iconReset:SetScript("OnClick", function()
		local s = slices()[selected]
		if s then
			s.icon = nil
			ns.Changed()
			setStatus(savedMessage())
		end
	end)

	buildSuggestions()
end

local function build()
	built = true
	buildHeader()
	buildBindings()
	buildList()
	buildEditor()
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
			local has = ns.Slices.HasAction(s)
			r.num:SetText(ns.Slices.KeyLabel(i))
			r.icon:SetTexture(ns.Slices.Icon(s))
			r.icon:SetDesaturated(not has)
			r.text:SetText(has and ns.Slices.Label(s) or "|cff888888(empty)|r")
			r.kind:SetText(has and KIND_LABEL[s.kind] or "")
			r.sel:SetShown(i == selected)
			r.selBar:SetShown(i == selected)
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
	hideSuggestions()
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
