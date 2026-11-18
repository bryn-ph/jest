-- Restricted-environment snippets: strings run by Blizzard's secure handler sandbox, which is
-- what lets the wheel open and fire in combat. Inside them:
--   * no addon globals or upvalues: only `self`, `button`, `down`, attributes and frame refs;
--   * `math`, `string`, `print`, `tostring`, `tonumber` are available; GetTime/GetCursorPosition are not;
--   * cursor position comes only from `$cursor` anchoring and handle:GetMousePosition().
local _, ns = ...

ns.Snippets = {}

-- Secure button name for slice `slice` of wheel `wheel`. SecureActionButtonTemplate turns button
-- "w2s3" into the attribute suffix "-w2s3" (type-w2s3, macrotext-w2s3, ...). The snippet below
-- builds the same names; keep the two in step.
function ns.Snippets.SliceButton(wheel, slice)
	return "w" .. wheel .. "s" .. slice
end

-- Pre-body for SecureHandlerWrapScript(JestWheelButton, "OnClick", ...).
-- Returning false cancels the click; returning "wWsK" fires slice K of wheel W.
--
-- Attributes (set by SecureWheel.Apply, out of combat):
--   wheels      number of wheels           slicesW    slice count of wheel W
--   maxslices   most slices on any wheel   deadzone   cancel radius, UIParent units
--   remember    reopen on the last wheel
-- Kept by the snippets: open, page (wheel showing), lastwheel/lastslice (for repeat).
--
-- Virtual buttons:
--   LeftButton  main key (Bindings.xml): down opens, up selects by mouse direction
--   repeat      repeat-last key (Bindings.xml): up re-fires the last slice
--   pickK       number keys, bound only while the wheel is open
--   cancel      Esc, bound only while the wheel is open
-- The mouse wheel is bound to JestPagerButton instead (OnPage below).
--
-- Bindings are only changed when the wheel opens or closes, never while it's open. Rebinding
-- from another key's event (the mouse wheel) while the open key was held lost that key's
-- release in game, so the wheel never fired.
ns.Snippets.OnClick = [=[
	local W = self:GetAttribute("wheels") or 0
	local page = self:GetAttribute("page") or 1
	if page > W then page = 1 end
	local N = self:GetAttribute("slices" .. page) or 0
	local open = self:GetAttribute("open")

	if button == "repeat" then
		if down then return false end
		local lw, ls = self:GetAttribute("lastwheel"), self:GetAttribute("lastslice")
		if lw and ls and lw <= W and ls <= (self:GetAttribute("slices" .. lw) or 0) then
			self:CallMethod("JestOnRepeat", ls, lw)
			return "w" .. lw .. "s" .. ls
		end
		return false
	end

	if button == "cancel" then
		if down or not open then return false end
		self:SetAttribute("open", false)
		self:ClearBindings()
		self:CallMethod("JestOnClose", nil, "cancel", page)
		return false
	end

	local pick = string.match(button, "^pick(%d+)$")
	if pick then
		if down or not open then return false end
		pick = tonumber(pick)
		if pick > N then return false end
		self:SetAttribute("open", false)
		self:ClearBindings()
		self:SetAttribute("lastwheel", page)
		self:SetAttribute("lastslice", pick)
		self:CallMethod("JestOnClose", pick, "key", page)
		return "w" .. page .. "s" .. pick
	end

	if button ~= "LeftButton" then return false end

	if down then
		if not self:GetAttribute("remember") then page = 1 end
		self:SetAttribute("page", page)
		N = self:GetAttribute("slices" .. page) or 0
		if N < 1 then return false end
		-- Re-pressing while already open simply re-centres (recovers a wheel stuck by a lost key-up).
		local anchor = self:GetFrameRef("anchor")
		anchor:ClearAllPoints()
		anchor:SetPoint("CENTER", "$cursor", "BOTTOMLEFT", 0, 0)
		self:SetAttribute("open", true)
		-- Partly scrolled notches from last time don't count towards this opening.
		local pager = self:GetFrameRef("pager")
		if pager then pager:SetAttribute("scrollcount", 0) end
		-- Number keys for the biggest wheel, so scrolling never needs a rebind. Picks beyond the
		-- wheel showing are ignored.
		self:ClearBindings()
		local keys = self:GetAttribute("maxslices") or N
		for i = 1, keys do
			if i <= 9 then
				self:SetBindingClick(true, tostring(i), "JestWheelButton", "pick" .. i)
			elseif i == 10 then
				self:SetBindingClick(true, "0", "JestWheelButton", "pick10")
			end
		end
		self:SetBindingClick(true, "ESCAPE", "JestWheelButton", "cancel")
		if W > 1 then
			self:SetBindingClick(true, "MOUSEWHEELDOWN", "JestPagerButton", "next")
			self:SetBindingClick(true, "MOUSEWHEELUP", "JestPagerButton", "prev")
		end
		self:CallMethod("JestOnOpen", page)
		return false
	end

	-- Main key released.
	if not open then return false end
	self:SetAttribute("open", false)
	self:ClearBindings()

	local anchor = self:GetFrameRef("anchor")
	local x, y = anchor:GetMousePosition()
	if not x or N < 1 then
		self:CallMethod("JestOnClose", nil, "cancel", page)
		return false
	end

	-- Same maths as Geometry.SliceAt in UI/Geometry.lua; keep the two identical.
	local dx = (x - 0.5) * anchor:GetWidth()
	local dy = (y - 0.5) * anchor:GetHeight()
	local dz = self:GetAttribute("deadzone") or 0
	if dx * dx + dy * dy < dz * dz then
		self:CallMethod("JestOnClose", nil, "deadzone", page)
		return false
	end
	local a = (90 - math.deg(math.atan2(dy, dx))) % 360
	local step = 360 / N
	local idx = math.floor((a + step / 2) / step) % N + 1

	self:SetAttribute("lastwheel", page)
	self:SetAttribute("lastslice", idx)
	self:CallMethod("JestOnClose", idx, "mouse", page)
	return "w" .. page .. "s" .. idx
]=]

-- _onclick for JestPagerButton (SecureHandlerClickTemplate), clicked by the mouse wheel while
-- the wheel is open: "next" / "prev" switch the wheel showing. It only changes attributes on
-- JestWheelButton (frame ref "wheel"); the key bindings stay as they are.
ns.Snippets.OnPage = [=[
	-- A mouse-wheel binding may deliver a down and an up per notch, or only one of them. Act on
	-- whichever comes first and skip its partner.
	if not down and self:GetAttribute("scrolled") then
		self:SetAttribute("scrolled", false)
		return
	end
	self:SetAttribute("scrolled", down)

	local wheel = self:GetFrameRef("wheel")
	if not wheel:GetAttribute("open") then return end
	local W = wheel:GetAttribute("wheels") or 0
	if W < 2 then return end
	local step
	if button == "next" then
		step = 1
	elseif button == "prev" then
		step = -1
	else
		return
	end

	-- Switch only after "scrollsteps" notches in the same direction, so a stray flick of the
	-- mouse wheel doesn't change wheels. Reversing starts the count again; so does opening.
	local need = wheel:GetAttribute("scrollsteps") or 1
	local count = self:GetAttribute("scrollcount") or 0
	if count * step < 0 then count = 0 end
	count = count + step
	if count * step < need then
		self:SetAttribute("scrollcount", count)
		return
	end
	self:SetAttribute("scrollcount", 0)

	local page = wheel:GetAttribute("page") or 1
	if page > W then page = 1 end
	page = (page - 1 + step) % W + 1
	wheel:SetAttribute("page", page)
	wheel:CallMethod("JestOnPage", page)
]=]
