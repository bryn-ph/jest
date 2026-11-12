-- The secure half of the wheel: protected frames, the wrapped click snippet, and Apply(), which
-- copies the saved config into secure attributes. Attributes can only be changed out of combat,
-- so Apply() queues itself during combat lockdown and runs on PLAYER_REGEN_ENABLED.
local _, ns = ...

local SW = {}
ns.SecureWheel = SW

local btn, anchor
local pending = false
local chatActions = {} -- [sliceIndex] = { kind, value } for emote/text slices (read by the `jest` type)

local function performChat(kind, value)
	if kind == "emote" then
		local fn = (C_ChatInfo and C_ChatInfo.PerformEmote) or DoEmote
		fn(value)
	elseif kind == "text" then
		local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		fn(value, "EMOTE")
	end
end

local function create()
	local header = CreateFrame("Frame", "JestHeader", UIParent, "SecureHandlerBaseTemplate")

	-- Invisible protected geometry reference: huge so GetMousePosition never returns nil.
	anchor = CreateFrame("Frame", "JestAnchor", UIParent, "SecureHandlerBaseTemplate")
	anchor:SetSize(10000, 10000)
	anchor:SetPoint("CENTER")
	anchor:EnableMouse(false)

	btn = CreateFrame("Button", "JestWheelButton", UIParent, "SecureActionButtonTemplate")
	btn:RegisterForClicks("AnyDown", "AnyUp")
	btn:SetAttribute("useOnKeyDown", false) -- actions fire on key UP; key DOWN only opens the wheel

	-- Custom secure type "jest": SecureActionButtonTemplate calls rawget(btn, "jest") insecurely.
	-- Used for emote/text slices so they go through the native chat APIs instead of macro text.
	function btn:jest(_, button)
		local i = tonumber(button and button:match("^slice(%d+)$"))
		local action = i and chatActions[i]
		if action then
			performChat(action.kind, action.value)
		end
	end

	-- Notifications from the snippet (CallMethod runs these as insecure code).
	function btn:JestOnOpen()
		ns.Skin.Open()
	end
	function btn:JestOnClose(idx, reason)
		ns.Skin.Close(idx, reason)
	end
	function btn:JestOnRepeat(idx)
		ns.Skin.Repeat(idx)
	end

	SecureHandlerSetFrameRef(btn, "anchor", anchor)
	SecureHandlerWrapScript(btn, "OnClick", header, ns.Snippets.OnClick)
end

function SW.IsReady()
	return btn ~= nil
end

-- Push the active profile into secure attributes. Returns true if applied now, false if queued.
function SW.Apply()
	if InCombatLockdown() or not btn then
		if not pending then
			pending = true
			ns.Print("Changes will apply when combat ends.")
		end
		return false
	end
	pending = false

	local profile = ns.DB.Profile()
	local slices = ns.DB.Wheel().slices

	for i = 1, ns.MAX_SLICES do
		btn:SetAttribute("type-slice" .. i, nil)
		btn:SetAttribute("macrotext-slice" .. i, nil)
		chatActions[i] = nil
	end

	for i, s in ipairs(slices) do
		if ns.Slices.HasAction(s) then
			if s.kind == "macro" then
				btn:SetAttribute("type-slice" .. i, "macro")
				btn:SetAttribute("macrotext-slice" .. i, s.value)
			else
				btn:SetAttribute("type-slice" .. i, "jest")
				chatActions[i] = { kind = s.kind, value = s.value }
			end
		end
	end

	btn:SetAttribute("count", #slices)
	-- Snippet works in UIParent units; the skin is scaled, so scale the dead zone to match.
	btn:SetAttribute("deadzone", profile.deadZone * profile.scale)
	local last = btn:GetAttribute("last")
	if last and last > #slices then
		btn:SetAttribute("last", nil)
	end

	ns.Skin.Rebuild()
	ns.Debug("applied", #slices, "slices")
	return true
end

-- Out-of-combat escape hatch for a wheel stuck open (e.g. key-up lost on alt-tab).
function SW.ForceClose(reason)
	if not btn or InCombatLockdown() then return end
	btn:SetAttribute("open", false)
	ClearOverrideBindings(btn)
	ns.Skin.Close(nil, reason or "force")
end

-- Fire an emote/text slice directly (used by `/jest test`). Macro slices need the secure path.
function SW.TestChat(i)
	local s = ns.DB.Wheel().slices[i]
	if ns.Slices.HasAction(s) and ns.Slices.IsChat(s) then
		performChat(s.kind, s.value)
		return true
	end
	return false
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if not btn then
		create()
	end
	if pending then
		if SW.Apply() then
			ns.Print("Queued changes applied.")
		end
	end
end)

-- Create the secure frames at load time. If the UI was reloaded mid-combat, defer (risk R6).
if InCombatLockdown() then
	ns.Print("Loaded during combat; the wheel will be ready when combat ends.")
else
	create()
end
