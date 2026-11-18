-- Jest's window (/jest, the minimap button, Options > AddOns > Jest): a standard game window
-- with pages behind its bottom tabs.
--   Wheels:  the wheel tabs, a wheel preview (click to select, drag to move) and the slice editor
--   Options: key bindings and settings (Config/Options.lua)
-- The Profile dropdown sits in the window's top band, on every page.
-- Edits write to the DB and call ns.Changed().
local addonName, ns = ...

local Panel = {}
ns.Panel = Panel

-- Preview wheel (a WheelView, the same drawing code as the in-game wheel), scaled down.
local PREVIEW = { radius = 88, deadZone = 22, iconSize = 30, centreIconSize = 32 }
local COLUMN_W = 2 * (PREVIEW.radius + PREVIEW.iconSize)
local CLICK_AFTER_DRAG = 0.2 -- ignore the click that some clients send right after a drag ends
local LEFT = 16          -- padding inside a page
local FIELD_X = 70       -- x of input controls inside the slice editor
local STATUS_SECONDS = 4 -- success messages clear themselves after this long

local UNDO_SECONDS = 10
local CURSOR_POLL = 0.1  -- how often the preview checks whether you're holding something droppable

-- Window layout
local WINDOW_W, WINDOW_H = 720, 470
local PAGE_TOP = -60      -- below the title bar and the top band (where the inset starts)
local LEFT_INSET_W = COLUMN_W + 28

-- Wheel tabs (native top tabs across the top of the Wheels page)
local TAB_H = 24
local TAB_MIN_W, TAB_MAX_W = 56, 120
local RENAME_EXTRA_W = 26 -- a tab being renamed is this much wider, so the whole name shows

-- Editor tabs. "action" covers every draggable kind in Core/Actions.lua (item, spell, mount...).
local KINDS = { "emote", "macro", "action" }
local KIND_LABEL = { emote = "Emote", macro = "Macro", action = "Action" }
local KIND_HINT = {
	emote = "Pick from every emote the game knows; type in the list to search. Tags show whether an emote animates (Anim) and/or speaks (Voice).",
	macro = "Any macro text, e.g. /cast or /use. For a custom emote line, use /e: /e twirls dramatically. Max 255 characters.",
	action = "Drag an item, spell, mount, toy, macro or equipment set onto this box, or onto any slice in the preview. Drops save straight away.",
}
local DROP_PROMPT = "Drag something here"

-- Editor tab for a slice kind.
local function tabFor(kind)
	return ns.Actions.IsAction(kind) and "action" or kind
end

-- Human name for a slice kind ("Item", "Macro", ...).
local function kindName(kind)
	return KIND_LABEL[kind] or ns.Actions.KindLabel(kind) or kind
end
local BIND_WHEEL = "CLICK JestWheelButton:LeftButton"
local BIND_REPEAT = "CLICK JestWheelButton:repeat"

-- The window isn't part of the game's Settings panel: while Settings is open the game refuses
-- to open its bags (and you drag things from your bags onto the wheel), and closing Settings
-- always brings up the Game Menu. Options > AddOns > Jest only has a button that opens this.
local window = ns.Widgets.NativeWindow("JestEditor", "Jest", WINDOW_W, WINDOW_H, {
	portrait = "Interface\\AddOns\\" .. addonName .. "\\Media\\icon",
	inset = false, -- each page draws its own inset panels
})
window:SetPoint("CENTER", -150, 30) -- left of centre, leaving room for bags on the right
window:SetFrameStrata("HIGH")

---------------------------------------------------------------------------
-- Pages, one per bottom tab
---------------------------------------------------------------------------
local pages = {}      -- [key] = { frame =, tab =, index = }
local currentPage

-- Add a page and its bottom tab. Returns the page frame (the area below the top band).
function Panel.AddPage(key, title)
	local index = #window.jestTabs + 1
	local page = CreateFrame("Frame", nil, window)
	page:SetPoint("TOPLEFT", 4, PAGE_TOP)
	page:SetPoint("BOTTOMRIGHT", -6, 4)
	page:Hide()

	local tab = CreateFrame("Button", "JestEditorTab" .. index, window, "PanelTabButtonTemplate")
	tab:SetID(index)
	tab:SetText(title)
	if index == 1 then
		tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 11, 2)
	end
	tab:SetScript("OnClick", function()
		Panel.ShowPage(key)
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		end
	end)
	window.jestTabs[index] = tab
	if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(window, index) end

	pages[key] = { frame = page, tab = tab, index = index }
	return page
end
window.jestTabs = {}

function Panel.ShowPage(key)
	local page = pages[key]
	if not page then return end
	currentPage = key
	for k, p in pairs(pages) do
		p.frame:SetShown(k == key)
	end
	if PanelTemplates_SetTab then PanelTemplates_SetTab(window, page.index) end
end

function Panel.CurrentPage()
	return currentPage
end

local canvas = Panel.AddPage("wheels", "Wheels")
-- The tab template resizes itself on show (and on display changes) from these parent fields.
canvas.minTabWidth, canvas.maxTabWidth = TAB_MIN_W, TAB_MAX_W
local category
local built = false
local ui = {}
Panel._ui = ui -- internal; used by the tests
Panel._canvas, Panel._window = canvas, window
local selected = 1
-- Unsaved edits for the selected slice: one draft value per kind, so switching between Emote
-- and Macro never loses what was typed. "Unsaved" is worked out by comparing with draft.slice.
local draft = { slice = nil, kind = "emote", values = {} }

local function slices()
	return ns.DB.Wheel().slices
end

local statusToken = 0
local function setStatus(text, isError)
	if not ui.status then return end
	if ui.undo then ui.undo:Hide() end -- a new message replaces any pending undo offer
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

-- The packager replaces the TOC's @project-version@ token; a source checkout shows "dev".
local function addonVersion()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = get and get(addonName, "Version")
	if not version or version:find("@", 1, true) then
		return "dev"
	end
	return version
end
Panel.Version = addonVersion

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

-- report(text, isError) shows messages (the page's status line).
local function createBindButton(parent, command, report)
	report = report or setStatus
	local b = button(parent, "", 150)
	b:RegisterForClicks("AnyUp")

	function b:Refresh()
		local key = GetBindingKey(command)
		self:SetText(key and keyText(key) or "|cff888888Not bound|r")
	end

	-- The OnKeyDown script is only set while capturing: a frame with one receives keyboard
	-- input, which would otherwise steal keys (e.g. Backspace) from the panel's text boxes.
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
			report("Key bindings can't be changed in combat.", true)
			return
		end
		local previous = GetBindingAction(key)
		clearBinding(command)
		if not SetBinding(key, command) then
			report("Couldn't bind " .. keyText(key) .. ".", true)
			self:Refresh()
			return
		end
		SaveBindings(GetCurrentBindingSet())
		self:Refresh()
		if previous and previous ~= "" and previous ~= command then
			local name = _G["BINDING_NAME_" .. previous] or previous
			report(("Bound %s. It was bound to \"%s\" before."):format(keyText(key), name))
		else
			report("Bound " .. keyText(key) .. ".")
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
			report("Key bindings can't be changed in combat.", true)
			return
		end
		if mouseButton == "RightButton" then
			clearBinding(command)
			SaveBindings(GetCurrentBindingSet())
			self:Refresh()
			report("Key cleared.")
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
Panel.CreateBindButton = createBindButton -- used by Config/Options.lua

---------------------------------------------------------------------------
-- Drafts
---------------------------------------------------------------------------
-- Emote and macro drafts are strings; the action draft is { kind = ..., value = ... } or nil.
local function draftValue()
	return draft.values[draft.kind] or ""
end

local function isDirty()
	local s = draft.slice
	if not s then return false end
	if draft.kind ~= tabFor(s.kind) then return true end
	if draft.kind == "action" then
		local a = draft.values.action
		return not (type(a) == "table" and a.kind == s.kind and a.value == s.value)
	end
	return draftValue() ~= (s.value or "")
end

local function loadDraft()
	local s = slices()[selected]
	draft.slice = s
	draft.kind = s and tabFor(s.kind) or "emote"
	draft.values = {}
	if s then
		if draft.kind == "action" then
			draft.values.action = { kind = s.kind, value = s.value }
		else
			draft.values[s.kind] = s.value or ""
		end
	end
end

-- An action as macro text, when there's an obvious equivalent.
local function actionAsMacro(a)
	local name = ns.Actions.Name(a.kind, a.value)
	if a.kind == "item" then return "/use item:" .. a.value end
	if not name then return "" end
	if a.kind == "mount" then
		local spell = ns.Actions.MountSpellName(a.value)
		return spell and ("/cast " .. spell) or ""
	end
	if a.kind == "spell" then return "/cast " .. name end
	if a.kind == "toy" then return "/use " .. name end
	if a.kind == "equipset" then return "/equipset " .. name end
	return ""
end

-- Best-effort translation of a draft into another tab ("" or nil when there's no sensible one).
local function convert(fromKind, v, toKind)
	if fromKind == toKind then return v end
	if fromKind == "action" then
		return (toKind == "macro" and type(v) == "table") and actionAsMacro(v) or ""
	end
	if toKind == "action" then return nil end -- only a drop can fill the action tab
	if v == "" then return "" end
	if toKind == "macro" then -- from emote: "WAVE" -> "/wave"
		local token = ns.Emotes.Resolve(v)
		return token and ("/" .. token:lower()) or ""
	elseif toKind == "emote" then -- from macro: a lone "/wave" -> "WAVE"
		local cmd = v:match("^(/%S+)%s*$")
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
		if (seeded == "" or seeded == nil) and s and tabFor(s.kind) ~= draft.kind then
			local savedTab = tabFor(s.kind)
			local savedValue = savedTab == "action" and { kind = s.kind, value = s.value } or (s.value or "")
			seeded = convert(savedTab, savedValue, newKind)
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
-- Emote dropdown (the action control for Emote slices)
---------------------------------------------------------------------------
local function updateEmoteDropdown(token)
	local b = ui.emoteDropdown
	b.value = token ~= "" and token or nil
	if b.value then
		b.text:SetText(ns.Emotes.Label(token))
		b.text:SetTextColor(1, 1, 1)
		b.cmd:SetText(ns.Emotes.Command(token) or "")
		b.badges:SetEmote(token)
		b.badges:Show()
	else
		b.text:SetText("Choose an emote...")
		b.text:SetTextColor(0.6, 0.6, 0.6)
		b.cmd:SetText("")
		b.badges:Hide()
	end
end

---------------------------------------------------------------------------
-- Action box (the drop target for Action slices)
---------------------------------------------------------------------------
local function updateActionBox(a)
	local b = ui.actionBox
	if type(a) == "table" then
		local slice = { kind = a.kind, value = a.value }
		local count = ns.Slices.Count(slice)
		b.icon:SetTexture(ns.Slices.Icon(slice))
		b.icon:Show()
		b.text:SetText(ns.Slices.Label(slice))
		b.text:SetTextColor(1, 1, 1)
		b.kind:SetText(kindName(a.kind) .. (count and (" x" .. count) or ""))
	else
		b.icon:Hide()
		b.text:SetText(DROP_PROMPT)
		b.text:SetTextColor(0.6, 0.6, 0.6)
		b.kind:SetText("")
	end
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
	local isMacro, isEmote, isAction = draft.kind == "macro", draft.kind == "emote", draft.kind == "action"
	ui.emoteDropdown:SetShown(isEmote)
	ui.multi:SetShown(isMacro)
	ui.actionBox:SetShown(isAction)
	if not isEmote then ns.EmoteMenu.Close() end
	if isEmote then
		updateEmoteDropdown(value)
	elseif isAction then
		updateActionBox(draft.values.action)
	elseif ui.multiBox:GetText() ~= value then
		ui.multiBox:SetText(value)
		ui.multiScroll:SetVerticalScroll(0)
	end

	-- The hint (and everything below it) follows whichever action control is visible.
	local control = (isMacro and ui.multi) or (isAction and ui.actionBox) or ui.emoteDropdown
	ui.hint:ClearAllPoints()
	ui.hint:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -6)
	ui.hint:SetPoint("RIGHT", ui.card, "RIGHT", -12, 0)
	local hint = KIND_HINT[draft.kind]
	if draft.kind ~= tabFor(s.kind) and ns.Slices.HasAction(s) then
		hint = ("|cffffd100Saved as %s: %s.|r Save to replace it, or switch back to keep it.\n%s"):format(
			kindName(s.kind), ns.Slices.Label({ kind = s.kind, value = s.value }), hint)
	end
	ui.hint:SetText(hint)
	ui.counter:SetText(isMacro and ("%d/%d"):format(#value, ns.Slices.MACRO_MAX) or "")

	if ui.labelBox:GetText() ~= (s.label or "") then
		ui.labelBox:SetText(s.label or "")
	end
	ns.Widgets.SetPlaceholder(ui.labelBox, ns.Slices.Label({ kind = s.kind, value = s.value }))
	ui.iconButton.icon:SetTexture(ns.Slices.Icon(s))
	ui.iconReset:SetEnabled(s.icon ~= nil)
	ui.test:SetEnabled(ns.Slices.IsEmote(s) and ns.Slices.HasAction(s))
	updateDirtyState()
end

function Panel.Save()
	local s = slices()[selected]
	if not s then return false end
	if draft.kind == "action" then
		local a = draft.values.action
		if type(a) ~= "table" or not ns.Actions.Valid(a.kind, a.value) then
			setStatus("Drag something onto the box first.", true)
			return false
		end
		s.kind, s.value = a.kind, a.value
	else
		local value, err = ns.Slices.Validate(draft.kind, draftValue())
		if not value then
			setStatus(err, true)
			return false
		end
		s.kind, s.value = draft.kind, value
	end
	loadDraft()
	ns.Changed() -- triggers Panel.Refresh via the change listener
	setStatus(savedMessage())
	return true
end

-- Picking an emote from the list is always valid, so it saves straight away.
local function pickEmote(token)
	draft.values.emote = token
	updateEmoteDropdown(token)
	Panel.Save()
end

local function openEmoteMenu()
	local current = draft.values.emote
	ns.EmoteMenu.Open(ui.emoteDropdown, current ~= "" and current or nil, pickEmote)
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
-- Dropping things from the game onto the wheel
---------------------------------------------------------------------------
-- Reverts the last drop or wheel deletion; returns false when that's no longer possible.
local undoAction

-- Show the Undo button next to the current status message. Call after setStatus, which hides it.
local function offerUndo(fn)
	undoAction = fn
	ui.undo:Show()
	local token = statusToken
	if C_Timer and C_Timer.After then
		C_Timer.After(UNDO_SECONDS, function()
			if token == statusToken then ui.undo:Hide() end
		end)
	end
end

local function runUndo()
	local fn = undoAction
	undoAction = nil
	if fn and fn() ~= false then
		setStatus("Undone.")
	else
		setStatus("Nothing to undo.", true)
	end
end

-- Put whatever is on the cursor into slice `index`, or a new slice when `index` is nil.
-- Returns true if something was dropped.
local function dropFromCursor(index)
	local dropped, err = ns.Actions.FromCursor()
	if not dropped then
		if err then
			ClearCursor()
			setStatus(err, true)
		end
		return false
	end
	local list = slices()
	if not index and #list >= ns.MAX_SLICES then
		setStatus(("The wheel holds at most %d slices."):format(ns.MAX_SLICES), true)
		return false
	end
	ClearCursor()
	settleDraft()

	local previous
	if index then
		previous = list[index]
		list[index] = dropped
	else
		table.insert(list, dropped)
		index = #list
	end
	selected = index
	loadDraft()
	ns.Changed()
	setStatus(("Slice %d is now %s."):format(index, ns.Slices.Label(dropped)))

	local wheel = ns.DB.Wheel()
	offerUndo(function()
		local w = ns.DB.IndexOfWheel(wheel)
		if not w or wheel.slices[index] ~= dropped then return false end
		settleDraft()
		if previous then
			wheel.slices[index] = previous
		else
			table.remove(wheel.slices, index)
		end
		ns.DB.SetEditIndex(w)
		selected = math.max(1, math.min(index, #wheel.slices))
		loadDraft()
		ns.Changed()
	end)
	return true
end

---------------------------------------------------------------------------
-- Preview wheel: click a slice to edit it, drag it to another place to move it there
---------------------------------------------------------------------------
local drag          -- { from = i, target = j } while a slice is being dragged (j = where it would go)
local lastDragEnd = 0

local function showSelectedInCentre()
	local s = ui.preview.slots[selected]
	if s and not s.empty then
		ui.preview:SetCentre(s.iconTexture, s.label)
	else
		ui.preview:SetCentre(nil, "Empty", true)
	end
end

local function slotTooltip(slot)
	if drag then return end
	local s = slices()[slot.index]
	if not s then return end
	GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.Slices.HasAction(s) and ns.Slices.Label(s) or "Empty slice", 1, 1, 1)
	if ns.Slices.HasAction(s) then
		local line
		if ns.Actions.IsAction(s.kind) then
			local count = ns.Slices.Count(s)
			line = kindName(s.kind) .. (count and (" x" .. count) or "")
		else
			line = kindName(s.kind) .. ": " .. s.value
		end
		GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
	end
	local key = ns.Slices.KeyLabel(slot.index)
	if key ~= "" then
		GameTooltip:AddLine("Press " .. key .. " while the wheel is open to fire it.", 0.5, 0.5, 0.5, true)
	end
	GameTooltip:AddLine("Click to edit. Drag to another place to move it there (the rest keep their order), or drop an item or spell here to replace it.", 0.5, 0.5, 0.5, true)
	GameTooltip:Show()
end

-- Cursor offset from the preview's centre, in the preview's own units.
local function previewCursorOffset()
	local f = ui.preview.frame
	local scale = f:GetEffectiveScale()
	local x, y = GetCursorPosition()
	local cx, cy = f:GetCenter()
	if not cx then return 0, 0 end
	return x / scale - cx, y / scale - cy
end

-- Slice under the cursor while dragging (same angle maths as the real wheel), or nil when the
-- cursor is in the centre or far outside the preview.
local function dropTarget()
	local dx, dy = previewCursorOffset()
	if dx * dx + dy * dy > COLUMN_W * COLUMN_W then return nil end
	return ns.Geometry.SliceAt(dx, dy, ui.preview.n, PREVIEW.deadZone)
end

local function clickSlice(i)
	-- Clicking while holding something (picked up from bags etc.) drops it here.
	if GetCursorInfo and GetCursorInfo() then
		dropFromCursor(i)
		return
	end
	if GetTime() - lastDragEnd < CLICK_AFTER_DRAG then return end
	Panel.Select(i)
end

-- Where slice k ends up when the dragged slice moves from `from` to `to`: the slices in between
-- close the gap it leaves and open one where it lands, so the order is kept.
local function movedIndex(k, from, to)
	if k == from then return to end
	if from < to and k > from and k <= to then return k - 1 end
	if from > to and k >= to and k < from then return k + 1 end
	return k
end
Panel._movedIndex = movedIndex -- internal; used by the tests

-- Slide the icons round the ring to show the order a drop at `to` would give (nil = as it is).
-- The dragged slice's own faded icon moves into the gap.
local function previewMove(to)
	for k = 1, ui.preview.n do
		ui.preview:SetSlotPosition(k, to and movedIndex(k, drag.from, to) or nil)
	end
end

local function updateDrag()
	local target = dropTarget()
	if target == drag.from then target = nil end
	if target ~= drag.target or drag.first then
		drag.first = nil
		drag.target = target
		previewMove(target)
		ui.preview:SetHighlight(target)
		ui.preview:SetEmphasis(nil)
		if target then
			ui.preview:SetCentre(ui.preview.slots[drag.from].iconTexture, ("Move to slot %d"):format(target))
		else
			ui.preview:SetCentre(nil, "Cancel", true)
		end
	end
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	ui.ghost:ClearAllPoints()
	ui.ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

-- While you hold something droppable (picked up from bags, spellbook, ...), say where it can go.
local holding = false
local sincePoll = 0

local function setHolding(now)
	holding = now
	local border = now and { 1, 0.82, 0, 1 } or { 0.6, 0.6, 0.6, 1 }
	ui.actionBox:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
	if now then
		ui.preview:SetCentre(nil, "Drop here to add", false)
	else
		showSelectedInCentre()
	end
end

local function updateDropHints(elapsed)
	sincePoll = sincePoll + elapsed
	if sincePoll < CURSOR_POLL then return end
	sincePoll = 0
	local now = ns.Actions.CursorHasAction()
	if now ~= holding then setHolding(now) end
end

local function startDrag(slot)
	settleDraft() -- slice indices are about to change
	GameTooltip:Hide()
	drag = { from = slot.index, first = true }
	slot:SetAlpha(0.35)
	ui.ghost.icon:SetTexture(slot.iconTexture)
	ui.ghost:Show()
	updateDrag()
end

local function endDrag(cancel)
	if not drag then return end
	local from = drag.from
	local target = not cancel and dropTarget() or nil
	if target == from then target = nil end
	if not target then previewMove(nil) end -- slide everything back home
	drag = nil
	lastDragEnd = GetTime()
	ui.ghost:Hide()
	local s = ui.preview.slots[from]
	if s then s:SetAlpha(1) end
	if not target then
		ui.preview:SetEmphasis(selected)
		ui.preview:SetHighlight(selected)
		if holding then setHolding(true) else showSelectedInCentre() end
		return
	end

	-- Insert, keeping the order of the rest. The preview already shows this order, so the
	-- re-layout that follows doesn't visibly move anything.
	local wheel = ns.DB.Wheel()
	local moved = table.remove(wheel.slices, from)
	table.insert(wheel.slices, target, moved)
	selected = target
	ns.Changed() -- refreshes the panel and the in-game wheel
	setStatus(("Moved slice %d to %d."):format(from, target))
	offerUndo(function()
		local w = ns.DB.IndexOfWheel(wheel)
		if not w or wheel.slices[target] ~= moved then return false end
		table.insert(wheel.slices, from, table.remove(wheel.slices, target))
		ns.DB.SetEditIndex(w)
		selected = from
		loadDraft()
		ns.Changed()
	end)
end

---------------------------------------------------------------------------
-- Wheel tabs: one per wheel, plus "+" to add one. Click to edit a wheel; double-click to rename;
-- right-click to rename, move or delete.
---------------------------------------------------------------------------
local startRename -- forward declaration (tabs and the rename box refer to each other)

local function selectWheel(i)
	if i == ns.DB.EditIndex() then return end
	endDrag(true)
	settleDraft()
	ns.DB.SetEditIndex(i)
	selected = 1
	loadDraft()
	Panel.Refresh()
end

local function addWheel()
	settleDraft()
	local index, err = ns.DB.AddWheel()
	if not index then
		setStatus(err, true)
		return
	end
	ns.DB.SetEditIndex(index)
	selected = 1
	loadDraft()
	ns.Changed()
	setStatus("Wheel added. Drop things onto its slices, and scroll to it while the wheel is open.")
	startRename(index) -- name it straight away, like a new folder
end

local function moveWheel(from, to)
	settleDraft()
	if ns.DB.MoveWheel(from, to) then
		ns.Changed()
	end
end

local function deleteWheel(i)
	settleDraft()
	local removed, err = ns.DB.RemoveWheel(i)
	if not removed then
		setStatus(err, true)
		return
	end
	selected = 1
	loadDraft()
	ns.Changed()
	setStatus(("Deleted \"%s\"."):format(removed.name))
	offerUndo(function()
		local index = ns.DB.InsertWheel(i, removed)
		if not index then return false end
		ns.DB.SetEditIndex(index)
		selected = 1
		loadDraft()
		ns.Changed()
	end)
end

local function renameWheel(i, text)
	local wheel = ns.DB.Wheels()[i]
	local name = ns.DB.CleanWheelName(text)
	if wheel and name and name ~= wheel.name then
		wheel.name = name
		ns.Changed()
		setStatus(savedMessage())
	end
end

-- Native top tab (PanelTopTabButtonTemplate). Selection uses the game's own tab helpers, but
-- PanelTemplates_SelectTab disables the tab, and a disabled button gets no double-clicks or
-- right-clicks; so re-enable it and show the selected (white) font as its normal font.
local TAB_HIGHLIGHTS = { "LeftHighlight", "MiddleHighlight", "RightHighlight" }
local function styleTab(tab, active)
	tab.jestSelected = active
	-- The template's hover glow (an additive copy of the tab art) shows as a pale block on these
	-- top tabs, and overhangs a selected one. Hide it: hovered tab text still turns white.
	for _, key in ipairs(TAB_HIGHLIGHTS) do
		local t = ns.Widgets.Child(tab, key)
		if t then t:SetAlpha(0) end
	end
	if active then
		if PanelTemplates_SelectTab then PanelTemplates_SelectTab(tab) end
		tab:Enable()
		tab:SetNormalFontObject(GameFontHighlightSmall)
	else
		if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
		tab:SetNormalFontObject(GameFontNormalSmall)
	end
end

local function createTab()
	local tab = CreateFrame("Button", nil, canvas, "PanelTopTabButtonTemplate")
	-- The template's text is tab.Text; keep a lower-case alias for the code below.
	tab.text = ns.Widgets.Child(tab, "Text") or tab:GetFontString()
	if not tab.text then -- only without the template (e.g. offline tests)
		tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tab:SetFontString(tab.text)
	end
	return tab
end

-- Size a tab to its text, like the game's own tabs. extra widens it (room for the rename box's
-- insets and cursor).
local function sizeTab(tab, extra)
	extra = extra or 0
	if PanelTemplates_TabResize then
		PanelTemplates_TabResize(tab, extra, nil, TAB_MIN_W, TAB_MAX_W + extra)
	else
		tab:SetWidth(TAB_MIN_W + extra)
	end
end

local function wheelMenu(tab)
	local i, count = tab.index, #ns.DB.Wheels()
	ns.Widgets.ShowMenu(tab, {
		{ text = "Rename", onClick = function() startRename(i) end },
		{ text = "Move left", disabled = i <= 1, onClick = function() moveWheel(i, i - 1) end },
		{ text = "Move right", disabled = i >= count, onClick = function() moveWheel(i, i + 1) end },
		{ text = "Delete", disabled = count <= 1, onClick = function() deleteWheel(i) end },
	})
end

local function wheelTab(i)
	local tab = ui.tabs[i]
	if tab then return tab end
	tab = createTab()
	tab.index = i
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local function onClick(self, mouseButton)
		-- Its right-click menu is anchored here, so clicks on the tab don't close it by
		-- themselves: right-click toggles it, left-click closes it.
		local menuOpenHere = ns.Widgets.MenuIsOpen() and ns.Widgets.MenuAnchor() == self
		ns.Widgets.CloseMenu()
		selectWheel(self.index)
		if mouseButton == "RightButton" and not menuOpenHere then
			wheelMenu(self)
		end
	end
	tab:SetScript("OnClick", onClick)
	-- The game sends any quick second click here instead of to OnClick, whichever mouse button
	-- it was (left then right counts too). Only two left clicks rename; anything else is a click.
	tab:SetScript("OnDoubleClick", function(self, mouseButton)
		if mouseButton == "LeftButton" then
			ns.Widgets.CloseMenu()
			startRename(self.index)
		else
			onClick(self, mouseButton)
		end
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self:GetText(), 1, 1, 1)
		GameTooltip:AddLine("Double-click to rename. Right-click to rename, move or delete.", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("In game, scroll the mouse wheel while the wheel is open to switch wheels.", 0.5, 0.5, 0.5, true)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ui.tabs[i] = tab
	return tab
end

local function layoutTabs()
	local wheels = ns.DB.Wheels()
	local editing = ns.DB.EditIndex()
	local box = ui.renameBox
	local previous
	for i, wheel in ipairs(wheels) do
		local tab = wheelTab(i)
		-- While renaming, size the tab to the name being typed: the box sits over it, and the
		-- tabs after it move along as the name grows. The tab's own label hides under the box.
		local renaming = box:IsShown() and box.index == i
		tab:SetText(renaming and box:GetText() or wheel.name)
		tab.text:SetAlpha(renaming and 0 or 1)
		sizeTab(tab, renaming and RENAME_EXTRA_W or 0)
		tab:ClearAllPoints()
		if previous then
			tab:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 0, 0)
		else
			tab:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", 8, -TAB_H)
		end
		styleTab(tab, i == editing)
		tab:Show()
		previous = tab
	end
	for i = #wheels + 1, #ui.tabs do
		ui.tabs[i]:Hide()
	end
	ui.newWheel:ClearAllPoints()
	ui.newWheel:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 0, 0)
	ui.newWheel:SetShown(#wheels < ns.MAX_WHEELS)
end

-- Inline rename: an edit box laid over the tab. Enter or clicking away saves; Esc cancels.
startRename = function(i)
	Panel.Refresh() -- make sure the tab exists and is laid out
	local tab = ui.tabs[i]
	local wheel = ns.DB.Wheels()[i]
	if not (tab and wheel) then return end
	local box = ui.renameBox
	box.index, box.cancelled = i, false
	box:ClearAllPoints()
	-- A selected top tab draws its label 4 below its centre (PanelTemplates_SelectTab); match it.
	box:SetPoint("LEFT", tab, "LEFT", 8, -4)
	box:SetPoint("RIGHT", tab, "RIGHT", -6, -4)
	-- Widen the tab before focusing: an edit box that gets its text while too narrow scrolls to
	-- the end ("eel 4") and doesn't scroll back once it's wide enough.
	box:Show()
	box:SetText(wheel.name)
	layoutTabs()
	box:SetCursorPosition(0)
	box:SetFocus()
	box:HighlightText()
	-- Its new width only applies on the next frame; reset the scroll again then.
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if box:IsShown() and box.index == i then
				box:SetCursorPosition(0)
				box:HighlightText()
			end
		end)
	end
end

local function buildTabs()
	ui.tabs = {}

	ui.newWheel = createTab()
	ui.newWheel:SetText("+")
	sizeTab(ui.newWheel)
	styleTab(ui.newWheel, false)
	ui.newWheel:SetScript("OnClick", addWheel)
	tooltip(ui.newWheel, "New wheel", ("Adds another wheel (up to %d). In game, scroll the mouse wheel while the wheel is open to move between them."):format(ns.MAX_WHEELS))

	local box = ns.Widgets.Input(canvas, TAB_MIN_W, ns.WHEEL_NAME_MAX)
	box:SetFontObject(GameFontHighlightSmall) -- the tab's font, so the tab's width fits the text
	box:SetHeight(16)
	-- The tab itself is the box's frame: drop the text box border art, which crowded its edges.
	for _, key in ipairs({ "Left", "Middle", "Right" }) do
		local t = ns.Widgets.Child(box, key)
		if t then t:Hide() end
	end
	box:SetFrameLevel((canvas:GetFrameLevel() or 0) + 10) -- above the tabs
	box:Hide()
	box:SetScript("OnTextChanged", function(self)
		if self:IsShown() then layoutTabs() end
	end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self)
		self.cancelled = true
		self:ClearFocus()
	end)
	box:HookScript("OnEditFocusLost", function(self)
		self:Hide()
		if not self.cancelled then renameWheel(self.index, self:GetText()) end
		layoutTabs() -- back to the saved name's width (also after Esc)
	end)
	ui.renameBox = box
end

---------------------------------------------------------------------------
-- Profiles: the header's dropdown. Each profile is a whole set of wheels plus appearance
-- settings; switching shows its first wheel.
---------------------------------------------------------------------------
-- After the profile's contents or this character's profile changed.
local function profileChanged(message)
	selected = 1
	loadDraft()
	ns.Changed()
	setStatus(message)
end

-- Undo for a copy or reset: put the profile's earlier contents back.
local function offerRestore(name, previous)
	offerUndo(function()
		if ns.DB.ProfileName() ~= name or not ns.DB.RestoreProfile(name, previous) then return false end
		selected = 1
		loadDraft()
		ns.Changed()
	end)
end

local function switchProfile(name)
	settleDraft()
	ns.DB.SetProfile(name)
	profileChanged(("Using profile \"%s\"."):format(name))
end

local function newProfile()
	ns.Widgets.Prompt("New profile", "", function(text)
		settleDraft()
		local name, err = ns.DB.NewProfile(text)
		if not name then return err end
		profileChanged(("Switched to \"%s\", which starts with the default wheel."):format(name))
	end)
end

local function copyProfile(from)
	settleDraft()
	local current = ns.DB.ProfileName()
	local previous, err = ns.DB.CopyProfile(from)
	if not previous then
		setStatus(err, true)
		return
	end
	profileChanged(("Copied \"%s\" into \"%s\"."):format(from, current))
	offerRestore(current, previous)
end

local function renameProfile()
	ns.Widgets.Prompt("Rename profile", ns.DB.ProfileName(), function(text)
		local name, err = ns.DB.RenameProfile(text)
		if not name then return err end
		Panel.Refresh()
		setStatus(("Renamed to \"%s\"."):format(name))
	end)
end

local function resetProfile()
	settleDraft()
	local current = ns.DB.ProfileName()
	local previous = ns.DB.ResetProfile()
	profileChanged(("Reset \"%s\" to the default wheel."):format(current))
	offerRestore(current, previous)
end

local function usedBy(name)
	local n = ns.DB.ProfileUsers(name)
	if n == 0 then return nil end
	return ("Used by %d character%s."):format(n, n == 1 and "" or "s")
end

-- Delete from the list's "x". The list stays open (re-shown) so several can go in a row.
local function deleteProfile(name, anchor)
	settleDraft()
	local removed, err = ns.DB.DeleteProfile(name)
	if not removed then
		setStatus(err, true)
		return
	end
	if removed.switchedTo then
		profileChanged(("Deleted \"%s\". This character now uses \"%s\"."):format(removed.name, removed.switchedTo))
	else
		Panel.Refresh()
		setStatus(("Deleted \"%s\"."):format(removed.name))
	end
	offerUndo(function()
		if not ns.DB.UndeleteProfile(removed) then return false end
		if removed.switchedTo then
			selected = 1
			loadDraft()
			ns.Changed()
		else
			Panel.Refresh()
		end
	end)
	if anchor and #ns.DB.ProfileNames() > 0 then Panel.OpenProfileMenu(anchor) end
end

-- The Profile dropdown: just the profiles. Click one to switch; "x" deletes it.
function Panel.OpenProfileMenu(anchor)
	local current = ns.DB.ProfileName()
	local names = ns.DB.ProfileNames()
	local items = {}
	for _, name in ipairs(names) do
		local item = {
			text = name,
			checked = name == current,
			tooltip = name == current and "This character's profile." or usedBy(name),
			onClick = name ~= current and function() switchProfile(name) end or nil,
		}
		if #names > 1 then
			item.onRemove = function() deleteProfile(name, anchor) end
			item.removeTooltip = name == current
				and "Delete this profile (this character moves to another one). You can undo it."
				or "Delete this profile. You can undo it."
		end
		items[#items + 1] = item
	end
	items[#items + 1] = { separator = true }
	items[#items + 1] = { text = "+ New profile...", onClick = newProfile,
		tooltip = "Make a new profile with the default wheel, and switch this character to it." }
	ns.Widgets.ShowMenu(anchor, items)
end

-- The "..." button: things to do to this character's profile.
function Panel.OpenProfileOptions(anchor)
	local current = ns.DB.ProfileName()
	local others = {}
	for _, name in ipairs(ns.DB.ProfileNames()) do
		if name ~= current then others[#others + 1] = name end
	end
	ns.Widgets.ShowMenu(anchor, {
		{ text = "Rename...", onClick = renameProfile, tooltip = "Every character using this profile keeps it." },
		{ text = "Copy from...", disabled = #others == 0,
			tooltip = "Replace this profile's wheels and settings with a copy of another profile's. You can undo it.",
			onClick = function()
				local items = { { text = "Copy into \"" .. current .. "\":", disabled = true } }
				for _, name in ipairs(others) do
					items[#items + 1] = { text = name, tooltip = usedBy(name), onClick = function() copyProfile(name) end }
				end
				ns.Widgets.ShowMenu(anchor, items)
			end },
		{ separator = true },
		{ text = "Reset to default wheel", onClick = resetProfile, tooltip = "You can undo it." },
	})
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
-- The window's top band, shown on every page: which profile this character uses.
local function buildHeader()
	local p = ns.Widgets.Dropdown(window, 210)
	p:SetPoint("TOPRIGHT", window, "TOPRIGHT", -46, -30)
	p:SetScript("OnClick", function(self)
		if ns.Widgets.MenuIsOpen() then
			ns.Widgets.CloseMenu()
		else
			Panel.OpenProfileMenu(self)
		end
	end)
	tooltip(p, "Profile", "Your wheels and their look. Each new character starts with its own profile. Pick another to switch, or make a new one. Profiles are shared across your account.")
	p.text = p.Text
	ui.profile = p

	local caption = label(window, "Profile", "GameFontNormal")
	caption:SetPoint("RIGHT", p, "LEFT", -10, 0)

	-- "...": rename, copy from or reset the profile in use.
	local more = button(window, "...", 32)
	more:SetPoint("LEFT", p, "RIGHT", 6, 0)
	more:SetScript("OnClick", function(self)
		if ns.Widgets.MenuIsOpen() then
			ns.Widgets.CloseMenu()
		else
			Panel.OpenProfileOptions(self)
		end
	end)
	tooltip(more, "Profile options", "Rename this profile, copy another profile into it, or reset it.")
	ui.profileOptions = more
end

-- An inset panel, as in the game's own windows (InsetFrameTemplate).
local function inset(parent)
	local f = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
	return f
end

local function buildPreview()
	-- Left inset: the wheel preview. Right inset (buildEditor): the selected slice.
	local left = inset(canvas)
	left:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -(TAB_H - 2))
	left:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 0, 0)
	left:SetWidth(LEFT_INSET_W)
	ui.leftInset = left

	ui.add = button(left, "Add slice", 96)
	ui.add:SetPoint("TOPLEFT", left, "TOPLEFT", 14, -12)
	ui.remove = button(left, "Remove", 96)
	ui.remove:SetPoint("LEFT", ui.add, "RIGHT", 4, 0)
	tooltip(ui.remove, "Remove", "Deletes the selected slice. The slices after it move up one place.")

	ui.preview = ns.WheelView.Create(canvas, {
		interactive = true,
		labelFont = "GameFontHighlightSmall",
		-- The in-game wheel's near-black segments vanish on the dark inset; use lighter slate here.
		wedgeColor = { 0.30, 0.31, 0.36, 0.9 },
		wedgeEmptyAlpha = 0.45,
		onSlotCreated = function(slot)
			slot:RegisterForClicks("LeftButtonUp")
			slot:RegisterForDrag("LeftButton")
			slot:SetScript("OnClick", function(self) clickSlice(self.index) end)
			slot:SetScript("OnReceiveDrag", function(self) dropFromCursor(self.index) end)
			slot:SetScript("OnDragStart", startDrag)
			slot:SetScript("OnDragStop", function() endDrag() end)
			slot:SetScript("OnEnter", slotTooltip)
			slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end,
	})
	local pf = ui.preview.frame
	pf:SetPoint("TOPLEFT", ui.add, "BOTTOMLEFT", 0, -10)
	pf:SetScript("OnUpdate", function(_, elapsed)
		if drag then
			updateDrag()
		else
			updateDropHints(elapsed)
		end
		ui.preview:Update(elapsed)
	end)

	-- The empty centre accepts drops too, adding a new slice.
	local centre = CreateFrame("Button", nil, pf)
	centre:SetSize(76, 76)
	centre:SetPoint("CENTER")
	centre:RegisterForClicks("LeftButtonUp")
	centre:SetScript("OnReceiveDrag", function() dropFromCursor(nil) end)
	centre:SetScript("OnClick", function()
		if GetCursorInfo and GetCursorInfo() then dropFromCursor(nil) end
	end)
	ui.centreDrop = centre


	-- The icon that follows the cursor while dragging.
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetSize(PREVIEW.iconSize + 4, PREVIEW.iconSize + 4)
	local ring = ghost:CreateTexture(nil, "BORDER")
	ring:SetColorTexture(1, 0.82, 0, 1)
	ring:SetAllPoints()
	ns.WheelView.AddCircleMask(ghost, ring)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetPoint("TOPLEFT", 2, -2)
	ghost.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	ns.CropIcon(ghost.icon)
	ns.WheelView.AddCircleMask(ghost, ghost.icon)
	ghost:Hide()
	ui.ghost = ghost

	local hint = label(left, "Click a slice to edit it, drag it to move it. Drop items, spells, mounts and more onto a slice, or into the centre to add one.", "GameFontDisableSmall")
	hint:SetPoint("TOP", ui.preview.caption, "BOTTOM", 0, -8) -- below the name pill; same width as the wheel
	hint:SetWidth(COLUMN_W)

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
		openEmoteMenu() -- new slices start as an emote: go straight to choosing one
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
end

local function buildEmoteDropdown(card)
	local b = ns.Widgets.Dropdown(card, 200)
	b:SetPoint("TOPLEFT", FIELD_X + 4, -80)
	b:SetPoint("RIGHT", card, "RIGHT", -16, 0)
	b.badges = ns.Widgets.EmoteBadges(b)
	b.badges:SetPoint("RIGHT", b.Arrow, "LEFT", -4, 2)
	b.cmd = label(b, "", "GameFontDisableSmall")
	b.cmd:SetPoint("RIGHT", b.badges, "LEFT", -6, 0)
	b.text = b.Text
	b.text:SetPoint("RIGHT", b.cmd, "LEFT", -6, 0)

	b:SetScript("OnClick", function()
		if ns.EmoteMenu.IsOpen() then
			ns.EmoteMenu.Close()
		else
			openEmoteMenu()
		end
	end)
	ui.emoteDropdown = b
end

-- Drop target for Action slices: shows what's there, takes whatever you drop on it.
local function buildActionBox(card)
	local b = CreateFrame("Button", nil, card, "BackdropTemplate")
	b:SetHeight(40)
	b:SetPoint("TOPLEFT", FIELD_X, -78)
	b:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	ns.Widgets.NativeBox(b)
	b:RegisterForClicks("LeftButtonUp")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(28, 28)
	b.icon:SetPoint("LEFT", 5, 0)
	ns.CropIcon(b.icon)
	b.text = label(b, "", "GameFontHighlight")
	b.text:SetPoint("TOPLEFT", 40, -5)
	b.text:SetPoint("RIGHT", -8, 0)
	b.text:SetWordWrap(false)
	b.kind = label(b, "", "GameFontDisableSmall")
	b.kind:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -3)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetPoint("TOPLEFT", 1, -1)
	hover:SetPoint("BOTTOMRIGHT", -1, 1)
	hover:SetColorTexture(1, 1, 1, 0.06)

	b:SetScript("OnReceiveDrag", function() dropFromCursor(selected) end)
	b:SetScript("OnClick", function()
		if GetCursorInfo and GetCursorInfo() then dropFromCursor(selected) end
	end)
	tooltip(b, "Action", "Drag an item, spell, mount, toy, macro or equipment set here. You can also drop onto any slice in the preview.")
	ui.actionBox = b
end

local function buildEditor()
	local right = inset(canvas)
	right:SetPoint("TOPLEFT", ui.leftInset, "TOPRIGHT", 4, 0)
	right:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 0, 0)
	-- Everything below is laid out on `card`, the right inset's content area.
	local card = CreateFrame("Frame", nil, right)
	card:SetPoint("TOPLEFT", 6, -4)
	card:SetPoint("BOTTOMRIGHT", -6, 4)
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
	ui.kindSwitch = ns.Widgets.Segmented(card, items, 210, function(kind)
		switchKind(kind)
		updateEditor()
	end)
	ui.kindSwitch:SetPoint("TOPLEFT", FIELD_X, -44)
	ui.kind = ui.kindSwitch.buttons

	-- Action
	local actionLabel = label(card, "Action", "GameFontHighlightSmall")
	actionLabel:SetPoint("TOPLEFT", 12, -86)

	buildEmoteDropdown(card)
	buildActionBox(card)

	ui.multi = CreateFrame("Frame", nil, card, "BackdropTemplate")
	ui.multi:SetHeight(84)
	ui.multi:SetPoint("TOPLEFT", FIELD_X, -80)
	ui.multi:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	ns.Widgets.NativeBox(ui.multi)
	ui.multi:EnableMouse(true)
	-- A multi-line EditBox grows with its text instead of clipping it, so it sits in a scroll
	-- frame: the wheel scrolls it, and typing keeps the cursor in view.
	local scroll = CreateFrame("ScrollFrame", nil, ui.multi)
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -6, 6)
	ui.multiScroll = scroll
	ui.multiBox = CreateFrame("EditBox", nil, scroll)
	ui.multiBox:SetMultiLine(true)
	ui.multiBox:SetAutoFocus(false)
	ui.multiBox:SetFontObject(ChatFontNormal)
	ui.multiBox:SetMaxLetters(ns.Slices.MACRO_MAX)
	ui.multiBox:SetWidth(1) -- set from the scroll frame once it has a size
	scroll:SetScrollChild(ui.multiBox)
	scroll:SetScript("OnSizeChanged", function(_, width) ui.multiBox:SetWidth(width) end)
	local function scrollTo(offset)
		scroll:SetVerticalScroll(math.max(0, math.min(offset, scroll:GetVerticalScrollRange())))
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		scrollTo(scroll:GetVerticalScroll() - delta * 14)
	end)
	-- y is the cursor's offset from the top of the box (negative), h its line height. The scroll
	-- range lags a frame behind new lines, so the move is applied on the next frame.
	ui.multiBox:SetScript("OnCursorChanged", function(_, _, y, _, h)
		local top = -y
		C_Timer.After(0, function()
			local current, height = scroll:GetVerticalScroll(), scroll:GetHeight()
			if top < current then
				scrollTo(top)
			elseif top + h > current + height then
				scrollTo(top + h - height)
			end
		end)
	end)
	-- Clicks on the empty part of the box (below the text) still focus it.
	ui.multi:SetScript("OnMouseDown", function() ui.multiBox:SetFocus() end)
	ui.multiBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	ui.multiBox:SetScript("OnEditFocusGained", function() ui.multi:SetBackdropBorderColor(1, 0.82, 0, 1) end)
	ui.multiBox:SetScript("OnEditFocusLost", function() ui.multi:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end)
	ui.multiBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			setDraftValue(self:GetText())
			ui.counter:SetText(("%d/%d"):format(#draftValue(), ns.Slices.MACRO_MAX))
		end
	end)

	ui.hint = label(card, "", "GameFontDisableSmall")
	ui.hint:SetPoint("TOPLEFT", ui.emoteDropdown, "BOTTOMLEFT", 0, -6) -- re-anchored in updateEditor
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
		elseif not ns.SecureWheel.TestEmote(ns.DB.EditIndex(), selected) then
			setStatus("Only emote slices can be tested here; other slices fire from the wheel.", true)
		end
	end)
	tooltip(ui.test, "Test", "Performs this emote now. Other kinds of slice (items, spells, macros...) only fire from the wheel.")

	-- Status is pinned to the card's bottom edge so messages never shift the layout.
	ui.undo = button(card, "Undo", 60)
	ui.undo:SetPoint("BOTTOMRIGHT", -12, 8)
	ui.undo:SetScript("OnClick", runUndo)
	ui.undo:Hide()
	ui.status = label(card, "", "GameFontHighlightSmall")
	ui.status:SetPoint("BOTTOMLEFT", 12, 10)
	ui.status:SetPoint("RIGHT", ui.undo, "LEFT", -8, 0)
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
	ui.labelBox = ns.Widgets.Input(card, 180, ns.LABEL_MAX)
	ui.labelBox:SetPoint("LEFT", labelLabel, "LEFT", FIELD_X - 12, 0)
	ui.labelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	ui.labelBox:HookScript("OnEditFocusLost", commitLabel)
	tooltip(ui.labelBox, "Label", "Name shown under the wheel when this slice is highlighted. Leave empty to use the default (shown in grey).")

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
end

local function build()
	built = true
	buildHeader()
	buildTabs()
	buildPreview()
	buildEditor()
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function Panel.Refresh()
	if not built then return end
	local list = slices()
	selected = math.max(1, math.min(selected, #list))
	if not drag then
		ui.preview:Layout(list, PREVIEW)
		for i = 1, #list do
			ui.preview.slots[i]:SetAlpha(1)
		end
		ui.preview:SetEmphasis(selected)
		ui.preview:SetHighlight(selected) -- eases from the previous selection
		if holding then
			setHolding(true)
		else
			showSelectedInCentre()
		end
	end
	layoutTabs()
	ui.add:SetEnabled(#list < ns.MAX_SLICES)
	ui.remove:SetEnabled(#list > 1)
	ui.profile.text:SetText(ns.DB.ProfileName())
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
	endDrag(true)
	settleDraft()
	ns.EmoteMenu.Close()
	ns.IconPicker.Close()
	ns.Widgets.CloseMenu()
	ns.Widgets.ClosePrompt()
	if ui.renameBox then ui.renameBox:ClearFocus() end
end)


ns.OnChanged(function()
	if canvas:IsShown() then Panel.Refresh() end
end)

-- Item names arriving, bag counts changing.
ns.OnVisualsStale(function()
	if canvas:IsShown() and built and not drag then Panel.Refresh() end
end)

-- Options > AddOns > Jest: a pointer to Jest's window.
local launcher = CreateFrame("Frame")
launcher:Hide()
launcher.OnCommit = function() end
launcher.OnDefault = function() end
launcher.OnRefresh = function() end
launcher:SetScript("OnShow", function(self)
	if self.built then return end
	self.built = true
	local title = label(self, "Jest", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", LEFT, -16)
	local text = label(self, "Jest has its own window, so you can drag things from your bags and spellbook onto your wheels. Open it any time with /jest or the minimap button.", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	text:SetPoint("RIGHT", self, "RIGHT", -LEFT, 0)
	local open = button(self, "Open Jest", 140)
	self.openButton = open
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
	open:SetScript("OnClick", function()
		-- Settings has to close: the game won't open bags while it's up.
		if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end
		Panel.Open()
	end)
end)

function Panel.Register()
	if category then return end
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		ns.Debug("Settings API unavailable; open Jest with /jest")
		return
	end
	category = Settings.RegisterCanvasLayoutCategory(launcher, "Jest")
	Settings.RegisterAddOnCategory(category)
end

-- Open the window, on `page` if given (otherwise where it was last).
function Panel.Open(page)
	if page or not currentPage then Panel.ShowPage(page or "wheels") end
	window:Show()
	window:Raise()
end

-- /jest and the addon compartment: open, or close if already open.
function Panel.Toggle()
	if window:IsShown() then
		window:Hide()
	else
		Panel.Open()
	end
end
