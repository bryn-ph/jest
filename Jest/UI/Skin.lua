-- The insecure, visual half of the wheel. It never decides what fires (the secure snippet does);
-- it mirrors the snippet's geometry to highlight the slice that WILL fire, and plays feedback.
-- Non-protected frames can be shown, moved and animated freely in combat.
local _, ns = ...

local Skin = {}
ns.Skin = Skin

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ICON_SIZE = 40
local CENTRE_ICON_SIZE = 36
local HOVER_SCALE = 1.2
local SCALE_SPEED = 18         -- higher = snappier hover scale easing
local HOVER_SOUND_GAP = 0.03   -- seconds; throttles tick spam when sweeping across slices
local WATCHDOG_SECONDS = 15    -- out of combat, force-close a wheel open this long (lost key-up)

local SOUNDS = {
	hover = "U_CHAT_SCROLL_BUTTON",
	fire = "IG_MAINMENU_OPTION_CHECKBOX_ON",
	cancel = "IG_MAINMENU_OPTION_CHECKBOX_OFF",
}

-- State
local n, radius, deadZoneUI = 0, 110, 28
local isOpen, openX, openY, openedAt = false, 0, 0, 0
local hovered
local lastHoverSound = 0
local slots = {}

local function play(which)
	local profile = ns.DB.Profile()
	if not (profile and profile.sounds) then return end
	local id = SOUNDKIT and SOUNDKIT[SOUNDS[which]]
	if id then PlaySound(id, "SFX") end
end

local function addCircleMask(parent, texture)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
end

local function solidCircle(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(r, g, b, a)
	t:SetPoint("CENTER")
	addCircleMask(parent, t)
	return t
end

local function cursorUI()
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	return x / s, y / s
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "JestSkin", UIParent)
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetClampedToScreen(true)
frame:EnableMouse(false)
frame:Hide()

local backdrop = solidCircle(frame, "BACKGROUND", 0, 0, 0, 0.55)
local deadDisc = solidCircle(frame, "BORDER", 1, 1, 1, 0.07)

local centreIcon = frame:CreateTexture(nil, "ARTWORK")
centreIcon:SetSize(CENTRE_ICON_SIZE, CENTRE_ICON_SIZE)
centreIcon:SetPoint("CENTER", 0, 10)
addCircleMask(frame, centreIcon)

local centreLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
centreLabel:SetPoint("TOP", centreIcon, "BOTTOM", 0, -4)

local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint:SetPoint("TOP", frame, "BOTTOM", 0, 4)

local function getSlot(i)
	local s = slots[i]
	if s then return s end
	s = CreateFrame("Frame", nil, frame)
	s:SetSize(ICON_SIZE, ICON_SIZE)

	s.glow = solidCircle(s, "BACKGROUND", 1, 0.82, 0.2, 0.45)
	s.glow:SetSize(ICON_SIZE * 1.55, ICON_SIZE * 1.55)
	s.glow:SetBlendMode("ADD")
	s.glow:Hide()

	s.ring = solidCircle(s, "BORDER", 0, 0, 0, 0.85)
	s.ring:SetSize(ICON_SIZE + 4, ICON_SIZE + 4)

	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetAllPoints()
	addCircleMask(s, s.icon)

	s.key = s:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	s.key:SetPoint("TOPLEFT", -3, 3)

	s.scale, s.target, s.x, s.y = 1, 1, 0, 0
	slots[i] = s
	return s
end

-- Scaling a frame also scales its anchor offsets, so re-anchor with offset / scale.
local function placeSlot(s)
	s:SetScale(s.scale)
	s:SetPoint("CENTER", frame, "CENTER", s.x / s.scale, s.y / s.scale)
end

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
	local s = idx and slots[idx]
	if s and not s.empty then
		centreIcon:SetTexture(s.iconTexture)
		centreIcon:SetDesaturated(s.locked)
		centreIcon:Show()
		centreLabel:SetText(s.label)
		centreLabel:SetTextColor(1, 1, 1)
	else
		centreIcon:Hide()
		centreLabel:SetText(idx and "Empty" or "Cancel")
		centreLabel:SetTextColor(0.6, 0.6, 0.6)
	end
end

local function setHover(idx, silent)
	if hovered and slots[hovered] then
		slots[hovered].target = 1
		slots[hovered].glow:Hide()
	end
	hovered = idx
	if idx and slots[idx] then
		slots[idx].target = HOVER_SCALE
		slots[idx].glow:Show()
		local now = GetTime()
		if not silent and now - lastHoverSound > HOVER_SOUND_GAP then
			lastHoverSound = now
			play("hover")
		end
	end
	updateCentre(idx)
end

frame:SetScript("OnUpdate", function(_, elapsed)
	if isOpen then
		local x, y = cursorUI()
		local idx = ns.Geometry.SliceAt(x - openX, y - openY, n, deadZoneUI)
		if idx ~= hovered then setHover(idx) end

		if GetTime() - openedAt > WATCHDOG_SECONDS and not InCombatLockdown() then
			ns.SecureWheel.ForceClose("watchdog")
		end
	end

	local k = math.min(1, elapsed * SCALE_SPEED)
	for i = 1, n do
		local s = slots[i]
		if math.abs(s.target - s.scale) > 0.002 then
			s.scale = s.scale + (s.target - s.scale) * k
			placeSlot(s)
		end
	end
end)

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function Skin.Rebuild()
	local profile = ns.DB.Profile()
	local slices = ns.DB.Wheel().slices
	n = #slices
	radius = profile.radius
	deadZoneUI = profile.deadZone * profile.scale

	frame:SetScale(profile.scale)
	local size = 2 * (radius + ICON_SIZE)
	frame:SetSize(size, size)
	backdrop:SetSize(2 * (radius + ICON_SIZE * 0.85), 2 * (radius + ICON_SIZE * 0.85))
	deadDisc:SetSize(2 * profile.deadZone, 2 * profile.deadZone)

	for i, slice in ipairs(slices) do
		local s = getSlot(i)
		s.x, s.y = ns.Geometry.SlicePosition(i, n, radius)
		s.scale, s.target = 1, 1
		s:ClearAllPoints()
		placeSlot(s)
		s.iconTexture = ns.Slices.Icon(slice)
		s.icon:SetTexture(s.iconTexture)
		s.label = ns.Slices.Label(slice)
		s.empty = not ns.Slices.HasAction(slice)
		s.chat = ns.Slices.IsChat(slice)
		s.icon:SetAlpha(s.empty and 0.35 or 1)
		s.key:SetText(ns.Slices.KeyLabel(i))
		s.glow:Hide()
		s:Show()
	end
	for i = n + 1, #slots do
		slots[i]:Hide()
	end
	hovered = nil
end

function Skin.Open()
	openX, openY = cursorUI() -- same point the snippet anchors to via $cursor
	local cx, cy = GetCursorPosition()
	local eff = frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / eff, cy / eff)

	local lockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
	for i = 1, n do
		local s = slots[i]
		s.locked = lockdown and s.chat or false
		s.icon:SetDesaturated(s.locked)
		s.target, s.scale = 1, 1
		placeSlot(s)
		s.glow:Hide()
	end

	if IsMouselooking() then
		hint:SetText("Release right-click to aim, or press 1-" .. math.min(n, 9))
	elseif lockdown then
		hint:SetText("Chat is restricted here; emotes may not send")
	else
		hint:SetText("")
	end

	hovered = nil
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
		local skinIdx = ns.Geometry.SliceAt(x - openX, y - openY, n, deadZoneUI)
		local verdict = (skinIdx == idx) and "|cff55ff55match|r" or "|cffff5555MISMATCH|r"
		ns.Debug("close", reason, "secure =", tostring(idx), "skin =", tostring(skinIdx), verdict)
	elseif ns.debug then
		ns.Debug("close", reason, "slice =", tostring(idx))
	end

	isOpen = false
	if idx then
		if hovered ~= idx then setHover(idx, true) end -- e.g. number-key pick: show what fired
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
