-- Secure half of the wheel: the protected frames, the wrapped click handler, and Apply(), which
-- copies the active profile into secure attributes. Attributes can't change during combat, so
-- Apply() defers itself until PLAYER_REGEN_ENABLED.
local _, ns = ...

local SW = {}
ns.SecureWheel = SW

local btn, anchor
local pending = false
-- [button name, e.g. "w2s3"] = function, run by the custom "jest" action type for slices that
-- have no secure action type of their own (emotes, battle pets).
local runners = {}
-- Copy of the wheels as last applied. The in-game wheel draws from this rather than the DB, so
-- what it shows always matches what the secure button will fire, even when edits made in
-- combat are still waiting to apply.
local applied = {}
local SliceButton = ns.Snippets.SliceButton

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
		local run = button and runners[button]
		if run then
			run()
		end
	end

	-- Called from the snippet through CallMethod.
	function btn:JestOnOpen(page)
		ns.Skin.Open(page)
	end
	function btn:JestOnPage(page)
		ns.Skin.ShowPage(page)
	end
	function btn:JestOnClose(idx, reason, page)
		ns.Skin.Close(idx, reason, page)
	end
	function btn:JestOnRepeat(idx, page)
		ns.Skin.Repeat(idx, page)
	end

	SecureHandlerSetFrameRef(btn, "anchor", anchor)
	SecureHandlerWrapScript(btn, "OnClick", header, ns.Snippets.OnClick)

	-- The mouse wheel clicks this while the wheel is open, to switch wheels. A separate button so
	-- scrolling never clicks JestWheelButton itself, whose release is what fires a slice.
	local pager = CreateFrame("Button", "JestPagerButton", UIParent, "SecureHandlerClickTemplate")
	pager:RegisterForClicks("AnyDown", "AnyUp")
	SecureHandlerSetFrameRef(pager, "wheel", btn)
	SecureHandlerSetFrameRef(btn, "pager", pager) -- so opening can reset its notch count
	pager:SetAttribute("_onclick", ns.Snippets.OnPage)
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
	local wheels = ns.DB.Wheels()

	for w = 1, ns.MAX_WHEELS do
		for i = 1, ns.MAX_SLICES do
			local suffix = "-" .. SliceButton(w, i)
			btn:SetAttribute("type" .. suffix, nil)
			for _, attribute in ipairs(ns.Actions.ATTRIBUTES) do
				btn:SetAttribute(attribute .. suffix, nil)
			end
		end
		btn:SetAttribute("slices" .. w, nil)
	end
	runners = {}
	applied = {}

	for w, wheel in ipairs(wheels) do
		applied[w] = { name = wheel.name, slices = ns.DB.Copy(wheel.slices) }
		btn:SetAttribute("slices" .. w, #wheel.slices)
		for i, s in ipairs(wheel.slices) do
			if ns.Slices.HasAction(s) then
				local name = SliceButton(w, i)
				local suffix = "-" .. name
				if s.kind == "macro" then
					btn:SetAttribute("type" .. suffix, "macro")
					btn:SetAttribute("macrotext" .. suffix, s.value)
				elseif s.kind == "emote" then
					local token = s.value
					btn:SetAttribute("type" .. suffix, "jest")
					runners[name] = function() performEmote(token) end
				else
					local actionType, attribute, value, run = ns.Actions.Binding(s.kind, s.value)
					if actionType then
						btn:SetAttribute("type" .. suffix, actionType)
						btn:SetAttribute(attribute .. suffix, value)
					elseif run then
						btn:SetAttribute("type" .. suffix, "jest")
						runners[name] = run
					end
				end
			end
		end
	end

	local maxSlices = 0
	for _, wheel in ipairs(wheels) do
		maxSlices = math.max(maxSlices, #wheel.slices)
	end
	btn:SetAttribute("wheels", #wheels)
	btn:SetAttribute("maxslices", maxSlices)
	btn:SetAttribute("remember", profile.rememberWheel and true or false)
	btn:SetAttribute("scrollsteps", profile.scrollSteps)
	-- The snippet measures in UIParent units, but the wheel is drawn scaled.
	btn:SetAttribute("deadzone", profile.deadZone * profile.scale)
	-- First apply after loading: start on the wheel this character had last (only used when
	-- "Reopen on last wheel used" is on; the snippet opens on wheel 1 otherwise).
	if btn:GetAttribute("page") == nil and JestCharDB and JestCharDB.lastWheel then
		btn:SetAttribute("page", JestCharDB.lastWheel)
	end
	if (btn:GetAttribute("page") or 1) > #wheels then
		btn:SetAttribute("page", 1)
	end
	-- Forget a "repeat last" target that no longer exists.
	local lw, ls = btn:GetAttribute("lastwheel"), btn:GetAttribute("lastslice")
	if lw and not (wheels[lw] and ls and ls <= #wheels[lw].slices) then
		btn:SetAttribute("lastwheel", nil)
		btn:SetAttribute("lastslice", nil)
	end

	ns.Skin.Rebuild()
	return true
end

-- The wheels as last applied: { { name =, slices = { ... } }, ... }. Empty before the first apply.
function SW.Applied()
	return applied
end

-- Out of combat only: close a wheel left open (e.g. the key-up was lost to an alt-tab).
function SW.ForceClose(reason)
	if not btn or InCombatLockdown() then return end
	btn:SetAttribute("open", false)
	ClearOverrideBindings(btn)
	ns.Skin.Close(nil, reason or "force")
end

-- Perform emote slice i of wheel w directly (the panel's Test button, /jest test). Macros need
-- the wheel.
function SW.TestEmote(w, i)
	local wheel = ns.DB.Wheel(w)
	local s = wheel and wheel.slices[i]
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
