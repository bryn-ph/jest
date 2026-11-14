-- Secure half of the wheel: the protected frames, the wrapped click handler, and Apply(), which
-- copies the active profile into secure attributes. Attributes can't change during combat, so
-- Apply() defers itself until PLAYER_REGEN_ENABLED.
local _, ns = ...

local SW = {}
ns.SecureWheel = SW

local btn, anchor
local pending = false
-- [slice index] = function, run by the custom "jest" action type for slices that have no
-- secure action type of their own (emotes, battle pets).
local runners = {}

local function performEmote(token)
	local perform = (C_ChatInfo and C_ChatInfo.PerformEmote) or DoEmote
	perform(token)
end

local function create()
	local header = CreateFrame("Frame", "JestHeader", UIParent, "SecureHandlerBaseTemplate")

	-- Invisible protected frame the snippet anchors to the cursor. It is huge so that
	-- GetMousePosition() always has the cursor inside it.
	anchor = CreateFrame("Frame", "JestAnchor", UIParent, "SecureHandlerBaseTemplate")
	anchor:SetSize(10000, 10000)
	anchor:SetPoint("CENTER")
	anchor:EnableMouse(false)

	btn = CreateFrame("Button", "JestWheelButton", UIParent, "SecureActionButtonTemplate")
	btn:RegisterForClicks("AnyDown", "AnyUp")
	btn:SetAttribute("useOnKeyDown", false) -- act on key up; key down only opens the wheel

	-- type = "jest": SecureActionButtonTemplate calls this method (as insecure code) for slices
	-- without a secure action type, e.g. emotes, which use the emote API rather than macro text.
	function btn:jest(_, button)
		local i = tonumber(button and button:match("^slice(%d+)$"))
		local run = i and runners[i]
		if run then
			run()
		end
	end

	-- Called from the snippet through CallMethod.
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

-- Push the active profile into secure attributes. Returns false if deferred until after combat.
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
		local suffix = "-slice" .. i
		btn:SetAttribute("type" .. suffix, nil)
		for _, attribute in ipairs(ns.Actions.ATTRIBUTES) do
			btn:SetAttribute(attribute .. suffix, nil)
		end
		runners[i] = nil
	end

	for i, s in ipairs(slices) do
		if ns.Slices.HasAction(s) then
			local suffix = "-slice" .. i
			if s.kind == "macro" then
				btn:SetAttribute("type" .. suffix, "macro")
				btn:SetAttribute("macrotext" .. suffix, s.value)
			elseif s.kind == "emote" then
				local token = s.value
				btn:SetAttribute("type" .. suffix, "jest")
				runners[i] = function() performEmote(token) end
			else
				local actionType, attribute, value, run = ns.Actions.Binding(s.kind, s.value)
				if actionType then
					btn:SetAttribute("type" .. suffix, actionType)
					btn:SetAttribute(attribute .. suffix, value)
				elseif run then
					btn:SetAttribute("type" .. suffix, "jest")
					runners[i] = run
				end
			end
		end
	end

	btn:SetAttribute("count", #slices)
	-- The snippet measures in UIParent units, but the wheel is drawn scaled.
	btn:SetAttribute("deadzone", profile.deadZone * profile.scale)
	local last = btn:GetAttribute("last")
	if last and last > #slices then
		btn:SetAttribute("last", nil)
	end

	ns.Skin.Rebuild()
	return true
end

-- Out of combat only: close a wheel left open (e.g. the key-up was lost to an alt-tab).
function SW.ForceClose(reason)
	if not btn or InCombatLockdown() then return end
	btn:SetAttribute("open", false)
	ClearOverrideBindings(btn)
	ns.Skin.Close(nil, reason or "force")
end

-- Perform emote slice i directly (the panel's Test button, /jest test). Macros need the wheel.
function SW.TestEmote(i)
	local s = ns.DB.Wheel().slices[i]
	if ns.Slices.HasAction(s) and ns.Slices.IsEmote(s) then
		performEmote(s.value)
		return true
	end
	return false
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if not btn then
		create()
	end
	if pending and SW.Apply() then
		ns.Print("Queued changes applied.")
	end
end)

-- Collections (e.g. the mount journal a mount slice reads its spell from) may not be ready when
-- the addon loads, so apply once more on entering the world.
ns.On("PLAYER_ENTERING_WORLD", function()
	ns.Off("PLAYER_ENTERING_WORLD")
	if btn and not InCombatLockdown() and JestDB then
		SW.Apply()
	end
end)

-- Secure frames can't be created during combat (e.g. after a /reload mid-fight).
if InCombatLockdown() then
	ns.Print("Loaded during combat; the wheel will be ready when combat ends.")
else
	create()
end
