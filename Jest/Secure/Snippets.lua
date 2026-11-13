-- Restricted-environment snippets: strings run by Blizzard's secure handler sandbox, which is
-- what lets the wheel open and fire in combat. Inside them:
--   * no addon globals or upvalues: only `self`, `button`, `down`, attributes and frame refs;
--   * `math`, `string`, `print`, `tostring`, `tonumber` are available; GetTime/GetCursorPosition are not;
--   * cursor position comes only from `$cursor` anchoring and handle:GetMousePosition().
local _, ns = ...

ns.Snippets = {}

-- Pre-body for SecureHandlerWrapScript(JestWheelButton, "OnClick", ...).
-- Returning false cancels the click; returning "sliceK" makes SecureActionButtonTemplate run
-- the type-sliceK / macrotext-sliceK attributes (button "sliceK" -> attribute suffix "-sliceK").
--
-- Virtual buttons:
--   LeftButton  main key (Bindings.xml): down opens, up selects by mouse direction
--   repeat      repeat-last key (Bindings.xml): up re-fires the last slice
--   pickK       number keys, bound only while the wheel is open
--   cancel      Esc, bound only while the wheel is open
ns.Snippets.OnClick = [=[
	local N = self:GetAttribute("count") or 0

	if button == "repeat" then
		if down then return false end
		local last = self:GetAttribute("last")
		if last and last <= N then
			self:CallMethod("JestOnRepeat", last)
			return "slice" .. last
		end
		return false
	end

	if button == "cancel" then
		if down or not self:GetAttribute("open") then return false end
		self:SetAttribute("open", false)
		self:ClearBindings()
		self:CallMethod("JestOnClose", nil, "cancel")
		return false
	end

	local pick = string.match(button, "^pick(%d+)$")
	if pick then
		if down or not self:GetAttribute("open") then return false end
		pick = tonumber(pick)
		self:SetAttribute("open", false)
		self:ClearBindings()
		self:SetAttribute("last", pick)
		self:CallMethod("JestOnClose", pick, "key")
		return "slice" .. pick
	end

	if button ~= "LeftButton" then return false end

	local anchor = self:GetFrameRef("anchor")

	if down then
		if N < 1 then return false end
		-- Re-pressing while already open simply re-centres (recovers a wheel stuck by a lost key-up).
		anchor:ClearAllPoints()
		anchor:SetPoint("CENTER", "$cursor", "BOTTOMLEFT", 0, 0)
		self:SetAttribute("open", true)
		self:ClearBindings()
		for i = 1, N do
			if i <= 9 then
				self:SetBindingClick(true, tostring(i), "JestWheelButton", "pick" .. i)
			elseif i == 10 then
				self:SetBindingClick(true, "0", "JestWheelButton", "pick10")
			end
		end
		self:SetBindingClick(true, "ESCAPE", "JestWheelButton", "cancel")
		self:CallMethod("JestOnOpen")
		return false
	end

	-- Main key released.
	if not self:GetAttribute("open") then return false end
	self:SetAttribute("open", false)
	self:ClearBindings()

	local x, y = anchor:GetMousePosition()
	if not x then
		self:CallMethod("JestOnClose", nil, "cancel")
		return false
	end

	-- Same maths as Geometry.SliceAt in UI/Geometry.lua; keep the two identical.
	local dx = (x - 0.5) * anchor:GetWidth()
	local dy = (y - 0.5) * anchor:GetHeight()
	local dz = self:GetAttribute("deadzone") or 0
	if dx * dx + dy * dy < dz * dz then
		self:CallMethod("JestOnClose", nil, "deadzone")
		return false
	end
	local a = (90 - math.deg(math.atan2(dy, dx))) % 360
	local step = 360 / N
	local idx = math.floor((a + step / 2) / step) % N + 1

	self:SetAttribute("last", idx)
	self:CallMethod("JestOnClose", idx, "mouse")
	return "slice" .. idx
]=]
