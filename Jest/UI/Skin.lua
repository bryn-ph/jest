-- Visual half of the in-game wheel. It never decides what fires (the secure snippet does); it
-- uses the same geometry to highlight the slice that will fire, and plays feedback sounds.
-- These frames aren't protected, so they can be shown and animated freely in combat.
local _, ns = ...

local Skin = {}
ns.Skin = Skin

local ICON_SIZE = 40
local CENTRE_ICON_SIZE = 36
local HOVER_SOUND_GAP = 0.03   -- seconds; throttles tick spam when sweeping across slices
local WATCHDOG_SECONDS = 15    -- out of combat, force-close a wheel open this long (lost key-up)

local SOUNDS = {
	hover = "U_CHAT_SCROLL_BUTTON",
	fire = "IG_MAINMENU_OPTION_CHECKBOX_ON",
	cancel = "IG_MAINMENU_OPTION_CHECKBOX_OFF",
}

-- State
local deadZoneUI = 28
local isOpen, openX, openY, openedAt = false, 0, 0, 0
local hovered
local lastHoverSound = 0

local function play(which)
	local profile = ns.DB.Profile()
	if not (profile and profile.sounds) then return end
	local id = SOUNDKIT and SOUNDKIT[SOUNDS[which]]
	if id then PlaySound(id, "SFX") end
end

local function cursorUI()
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	return x / s, y / s
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local view = ns.WheelView.Create(UIParent, { name = "JestSkin" })
local frame = view.frame
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetClampedToScreen(true)
frame:EnableMouse(false)
frame:Hide()

local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint:SetPoint("TOP", frame, "BOTTOM", 0, 4)

Skin._view = view -- internal; used by the tests

---------------------------------------------------------------------------
-- Animations
---------------------------------------------------------------------------
local openAnim = frame:CreateAnimationGroup()
do
	local fade = openAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.12)
	fade:SetSmoothing("OUT")
	local grow = openAnim:CreateAnimation("Scale")
	grow:SetScaleFrom(0.85, 0.85)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.12)
	grow:SetSmoothing("OUT")
end

local closeAnim = frame:CreateAnimationGroup()
closeAnim:SetToFinalAlpha(true)
do
	local fade = closeAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(0.08)
end
closeAnim:SetScript("OnFinished", function()
	frame:Hide()
end)

---------------------------------------------------------------------------
-- Hover / centre
---------------------------------------------------------------------------
local function updateCentre(idx)
	local s = idx and view.slots[idx]
	if s and not s.empty then
		view:SetCentre(s.iconTexture, s.label)
		view.centreIcon:SetDesaturated(s.locked)
	else
		view:SetCentre(nil, idx and "Empty" or "Cancel", true)
	end
end

local function setHover(idx, silent)
	hovered = idx
	view:SetEmphasis(idx)
	view:SetHighlight(idx)
	if idx and not silent then
		local now = GetTime()
		if now - lastHoverSound > HOVER_SOUND_GAP then
			lastHoverSound = now
			play("hover")
		end
	end
	updateCentre(idx)
end

frame:SetScript("OnUpdate", function(_, elapsed)
	if isOpen then
		local x, y = cursorUI()
		local idx = ns.Geometry.SliceAt(x - openX, y - openY, view.n, deadZoneUI)
		if idx ~= hovered then setHover(idx) end

		if GetTime() - openedAt > WATCHDOG_SECONDS and not InCombatLockdown() then
			ns.SecureWheel.ForceClose("watchdog")
		end
	end
	view:Update(elapsed)
end)

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function Skin.Rebuild()
	local profile = ns.DB.Profile()
	deadZoneUI = profile.deadZone * profile.scale
	frame:SetScale(profile.scale)
	view:Layout(ns.DB.Wheel().slices, {
		radius = profile.radius,
		deadZone = profile.deadZone,
		iconSize = ICON_SIZE,
		centreIconSize = CENTRE_ICON_SIZE,
	})
	hovered = nil
end

function Skin.Open()
	openX, openY = cursorUI() -- same point the snippet anchors to via $cursor
	local cx, cy = GetCursorPosition()
	local eff = frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / eff, cy / eff)

	local lockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
	view:ResetSlots()
	for i = 1, view.n do
		local s = view.slots[i]
		s.locked = lockdown and s.isEmote or false
		s.icon:SetDesaturated(s.locked)
	end

	if IsMouselooking() then
		hint:SetText("Release right-click to aim, or press 1-" .. math.min(view.n, 9))
	elseif lockdown then
		hint:SetText("Chat is restricted here; emotes may not send")
	else
		hint:SetText("")
	end

	hovered = nil
	view:ResetHighlight()
	updateCentre(nil)
	isOpen = true
	openedAt = GetTime()
	closeAnim:Stop()
	frame:SetAlpha(1)
	frame:Show()
	openAnim:Stop()
	openAnim:Play()
end

-- idx: slice that fired (nil = cancelled). reason: "mouse" | "key" | "deadzone" | "cancel" | ...
function Skin.Close(idx, reason)
	if ns.debug and (reason == "mouse" or reason == "deadzone") then
		local x, y = cursorUI()
		local skinIdx = ns.Geometry.SliceAt(x - openX, y - openY, view.n, deadZoneUI)
		local verdict = (skinIdx == idx) and "|cff55ff55match|r" or "|cffff5555MISMATCH|r"
		ns.Debug("close", reason, "secure =", tostring(idx), "skin =", tostring(skinIdx), verdict)
	elseif ns.debug then
		ns.Debug("close", reason, "slice =", tostring(idx))
	end

	isOpen = false
	if idx then
		if hovered ~= idx then setHover(idx, true) end -- e.g. number-key pick: show what fired
		view:Flash(idx) -- keep the fired slice lit at full strength for the fade-out
		play("fire")
	else
		play("cancel")
	end
	if frame:IsShown() then
		openAnim:Stop()
		closeAnim:Play()
	end
end

function Skin.Repeat(idx)
	ns.Debug("repeat slice", idx)
	play("fire")
end
