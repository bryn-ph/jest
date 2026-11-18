-- The Options page of Jest's window: key bindings, wheel size and scrolling, sounds and the
-- minimap button. Profile settings write to the DB and call ns.Changed().
local _, ns = ...

local Options = {}
ns.Options = Options

local BIND_WHEEL = "CLICK JestWheelButton:LeftButton"
local BIND_REPEAT = "CLICK JestWheelButton:repeat"
local PAD = 18
local ROW = 30 -- vertical step between controls
local STATUS_SECONDS = 4

local page = ns.Panel.AddPage("options", "Options")
local built = false
local controls = {}  -- everything with a :Refresh()
local ui = {}
Options._ui = ui -- internal; used by the tests
Options._page = page

local statusToken = 0
local function setStatus(text, isError)
	ui.status:SetText(text or "")
	if isError then
		ui.status:SetTextColor(1, 0.35, 0.35)
	else
		ui.status:SetTextColor(0.5, 1, 0.5)
	end
	statusToken = statusToken + 1
	local token = statusToken
	if text and text ~= "" and not isError and C_Timer and C_Timer.After then
		C_Timer.After(STATUS_SECONDS, function()
			if token == statusToken then ui.status:SetText("") end
		end)
	end
end

local function label(parent, text, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetText(text)
	fs:SetJustifyH("LEFT")
	return fs
end

local function profileSetter(key)
	return function(v)
		ns.DB.Profile()[key] = v
		ns.Changed()
	end
end

local function profileGetter(key)
	return function() return ns.DB.Profile()[key] end
end

-- A slider for a numeric profile setting with limits in ns.Limits.
local function slider(parent, key, text, step, format, tooltipText)
	local limits = ns.Limits[key]
	local s = ns.Widgets.Slider(parent, text, limits[1], limits[2], step, format, profileGetter(key), profileSetter(key))
	if tooltipText then
		s:EnableMouse(true)
		s:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText(text, 1, 1, 1)
			GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		s:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	controls[#controls + 1] = s
	ui[key] = s
	return s
end

local function check(parent, key, text, tooltipText, get, set)
	local c = ns.Widgets.Check(parent, text, tooltipText, get, set)
	controls[#controls + 1] = c
	ui[key] = c
	return c
end

local function build()
	built = true
	local box = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
	box:SetAllPoints()

	-- Key bindings
	local keys = ns.Widgets.Header(box, "Key bindings")
	keys:SetPoint("TOPLEFT", PAD, -16)
	local wheelLabel = label(box, "Open wheel")
	wheelLabel:SetPoint("TOPLEFT", keys, "BOTTOMLEFT", 0, -16)
	ui.bindWheel = ns.Panel.CreateBindButton(box, BIND_WHEEL, setStatus)
	ui.bindWheel:SetPoint("LEFT", wheelLabel, "LEFT", 100, 0)
	local repeatLabel = label(box, "Repeat last")
	repeatLabel:SetPoint("LEFT", ui.bindWheel, "RIGHT", 30, 0)
	ui.bindRepeat = ns.Panel.CreateBindButton(box, BIND_REPEAT, setStatus)
	ui.bindRepeat:SetPoint("LEFT", repeatLabel, "RIGHT", 12, 0)
	controls[#controls + 1] = ui.bindWheel
	controls[#controls + 1] = ui.bindRepeat
	local keyHint = label(box, "Hold the Open wheel key, aim at a slice and let go. Let go in the centre, or press Esc, to cancel. To set a key, click its button and press the key; right-click a button to clear it.", "GameFontDisableSmall")
	keyHint:SetPoint("TOPLEFT", wheelLabel, "BOTTOMLEFT", 0, -14)
	keyHint:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)

	-- The wheel
	local wheel = ns.Widgets.Header(box, "The wheel")
	wheel:SetPoint("TOPLEFT", keyHint, "BOTTOMLEFT", 0, -20)
	local function whole(v) return ("%d"):format(v) end
	local y = -16
	local rows = {
		slider(box, "radius", "Ring radius", 1, whole, "Distance from the centre of the wheel to the slice icons."),
		slider(box, "deadZone", "Cancel zone", 1, whole, "Letting go of the key this close to the centre cancels."),
		slider(box, "scale", "Wheel scale", 0.05, function(v) return ("%.2f"):format(v) end, "Overall size of the wheel."),
		slider(box, "scrollSteps", "Scroll to switch wheels", 1,
			function(v) return ("%d notch%s"):format(v, v == 1 and "" or "es") end,
			"With more than one wheel: how many notches of the mouse wheel it takes to switch to the next one. Higher is harder to do by accident."),
	}
	for _, row in ipairs(rows) do
		row:SetPoint("TOPLEFT", wheel, "BOTTOMLEFT", 0, y)
		y = y - ROW
	end
	local remember = check(box, "rememberWheel", "Reopen on the last wheel used",
		"With more than one wheel: open on whichever wheel you used last, even after a reload. Off: it always opens on the first wheel, so every direction stays the same.",
		profileGetter("rememberWheel"), profileSetter("rememberWheel"))
	remember:SetPoint("TOPLEFT", wheel, "BOTTOMLEFT", -4, y - 2)

	-- General
	local general = ns.Widgets.Header(box, "General")
	general:SetPoint("TOPLEFT", wheel, "BOTTOMLEFT", 0, y - 40)
	local sounds = check(box, "sounds", "Sounds", "Play sounds when hovering, firing and cancelling.",
		profileGetter("sounds"), profileSetter("sounds"))
	sounds:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -4, -10)
	local minimap = check(box, "minimap", "Minimap button", "Show the Jest button on the minimap's edge. Applies to all characters.",
		function() return ns.MinimapButton.IsShown() end,
		function(v) ns.MinimapButton.SetShown(v) end)
	minimap:SetPoint("LEFT", sounds, "LEFT", 220, 0) -- same row, to fit the shorter window

	-- Footer: version, chat commands, and messages from the key binding buttons.
	local footer = label(box, ("Jest %s. Type /jest help for chat commands."):format(ns.Panel.Version()), "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", PAD, 12)
	ui.status = label(box, "", "GameFontHighlightSmall")
	ui.status:SetPoint("BOTTOMRIGHT", -PAD, 12)
	ui.status:SetJustifyH("RIGHT")
end

function Options.Refresh()
	if not built then return end
	for _, c in ipairs(controls) do
		c:Refresh()
	end
end

page:SetScript("OnShow", function()
	if not built then build() end
	Options.Refresh()
end)

ns.OnChanged(function()
	if page:IsShown() then Options.Refresh() end
end)
