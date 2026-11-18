-- Visual half of the in-game wheel. It never decides what fires (the secure snippet does); it
-- uses the same geometry to highlight the slice that will fire, and plays feedback sounds.
-- These frames aren't protected, so they can be shown and animated freely in combat.
local _, ns = ...

local Skin = {}
ns.Skin = Skin

local ICON_SIZE = 40
local CENTRE_ICON_SIZE = 44
local HOVER_SOUND_GAP = 0.03   -- seconds; throttles tick spam when sweeping across slices
local WATCHDOG_SECONDS = 15    -- out of combat, force-close a wheel open this long (lost key-up)

local SOUNDS = {
	hover = "U_CHAT_SCROLL_BUTTON",
	fire = "IG_MAINMENU_OPTION_CHECKBOX_ON",
	cancel = "IG_MAINMENU_OPTION_CHECKBOX_OFF",
	page = "IG_ABILITY_PAGE_TURN",
}
local PAGER_GAP = 6            -- between the wheel's outer edge and the page dots
local DOT_SIZE, DOT_SPACING = 6, 11

-- State
local deadZoneUI = 28
local isOpen, openX, openY, openedAt = false, 0, 0, 0
local hovered
local lastHoverSound = 0
local page = 1                 -- wheel showing (index into SecureWheel.Applied())
local lockdown = false         -- chat lockdown when the wheel opened; greys emote slices
local layoutOpts

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
local view = ns.WheelView.Create(UIParent, { name = "JestSkin", cooldowns = true })
local frame = view.frame
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetClampedToScreen(true)
frame:EnableMouse(false)
frame:Hide()

local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint:SetPoint("TOP", view.caption, "BOTTOM", 0, -4) -- under the name pill

-- With more than one wheel: the wheel's name and a dot per wheel, above the ring.
local pager = CreateFrame("Frame", nil, frame)
pager:SetSize(1, 1)
pager:Hide()
local pagerName = ns.WheelView.CreatePill(pager, "GameFontNormal")
local dots = {}
for i = 1, ns.MAX_WHEELS do
	local dot = pager:CreateTexture(nil, "OVERLAY")
	dot:SetSize(DOT_SIZE, DOT_SIZE)
	dot:SetColorTexture(1, 1, 1, 1)
	ns.WheelView.AddCircleMask(pager, dot)
	dots[i] = dot
end
pagerName:SetPoint("BOTTOM", pager, "CENTER", 0, DOT_SIZE / 2 + 4)

Skin._view = view -- internal; used by the tests
Skin._pagerName = pagerName

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

-- A quick dip and settle when scrolling to another wheel.
local pageAnim = frame:CreateAnimationGroup()
do
	local fade = pageAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.45)
	fade:SetToAlpha(1)
	fade:SetDuration(0.14)
	fade:SetSmoothing("OUT")
	local grow = pageAnim:CreateAnimation("Scale")
	grow:SetScaleFrom(0.94, 0.94)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.14)
	grow:SetSmoothing("OUT")
end

---------------------------------------------------------------------------
-- Wheels
---------------------------------------------------------------------------
local function wheels()
	return ns.SecureWheel.Applied()
end

local function pageSlices()
	local w = wheels()[page]
	return w and w.slices or {}
end

local function updatePager()
	local list = wheels()
	local count = #list
	pager:SetShown(count > 1)
	if count <= 1 then return end
	pagerName:SetLabel(list[page] and list[page].name or "")
	local left = -(count - 1) * DOT_SPACING / 2
	for i, dot in ipairs(dots) do
		if i <= count then
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", pager, "CENTER", left + (i - 1) * DOT_SPACING, 0)
			if i == page then
				dot:SetVertexColor(1, 0.82, 0.2, 1)
			else
				dot:SetVertexColor(1, 1, 1, 0.35)
			end
			dot:Show()
		else
			dot:Hide()
		end
	end
end

-- Mark emote slices unusable while chat is locked down, then refresh icons, labels and counts.
local function refreshSlots()
	local slices = pageSlices()
	for i = 1, view.n do
		view.slots[i].locked = lockdown and ns.Slices.IsEmote(slices[i]) or false
	end
	view:RefreshContent(slices)
	view:RefreshCooldowns(slices)
end

-- Lay out wheel p (clamped to the wheels that exist).
local function showWheel(p)
	page = (wheels()[p] and p) or 1
	if layoutOpts then
		view:Layout(pageSlices(), layoutOpts)
	end
	updatePager()
end

---------------------------------------------------------------------------
-- Hover / centre
---------------------------------------------------------------------------
local function updateCentre(idx)
	local s = idx and view.slots[idx]
	if s and not s.empty then
		view:SetCentre(s.iconTexture, s.label)
		view.centreIcon:SetDesaturated(s.locked or s.outOfStock or false)
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
	layoutOpts = {
		radius = profile.radius,
		deadZone = profile.deadZone,
		iconSize = ICON_SIZE,
		centreIconSize = CENTRE_ICON_SIZE,
	}
	local outer = profile.radius + ICON_SIZE * 0.85 -- matches WheelView's outer edge
	pager:ClearAllPoints()
	pager:SetPoint("CENTER", frame, "CENTER", 0, outer + PAGER_GAP)
	pagerName.maxWidth = 2 * outer
	showWheel(page)
	hovered = nil
end

-- Cooldowns that start or end while the wheel is open (e.g. the global cooldown after a cast).
local function refreshCooldowns()
	if isOpen then view:RefreshCooldowns(pageSlices()) end
end
ns.On("SPELL_UPDATE_COOLDOWN", refreshCooldowns)
ns.On("BAG_UPDATE_COOLDOWN", refreshCooldowns)

ns.OnVisualsStale(function()
	if view.n > 0 then
		refreshSlots()
	end
end)

-- p: the wheel the snippet opened on.
function Skin.Open(p)
	if p and p ~= page then showWheel(p) end
	openX, openY = cursorUI() -- same point the snippet anchors to via $cursor
	local cx, cy = GetCursorPosition()
	local eff = frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / eff, cy / eff)

	lockdown = (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) or false
	view:ResetSlots()
	refreshSlots() -- current counts; greys locked and used-up slices

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

-- Scrolled to wheel p while open.
function Skin.ShowPage(p)
	if not isOpen then return end
	showWheel(p)
	view:ResetSlots()
	refreshSlots()
	hovered = nil
	view:ResetHighlight()
	updateCentre(nil) -- the next frame's hover check picks the slice under the cursor
	play("page")
	pageAnim:Stop()
	pageAnim:Play()
end

-- idx: slice that fired (nil = cancelled). reason: "mouse" | "key" | "deadzone" | "cancel" | ...
-- p: the wheel it was on.
function Skin.Close(idx, reason, p)
	if p and p ~= page then showWheel(p) end
	if p and JestCharDB then JestCharDB.lastWheel = p end -- survives a reload
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

function Skin.Repeat(idx, p)
	ns.Debug("repeat slice", idx, "of wheel", p)
	play("fire")
end
