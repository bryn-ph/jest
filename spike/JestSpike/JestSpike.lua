-- JestSpike: throwaway feasibility test for the Jest emote wheel.
-- Each check prints a tag like [S3] so results are easy to match against the plan (§8).
--
-- Wheel layout in the spike (4 slices, clockwise from the top):
--   1 = top    : macro path   "/dance"
--   2 = right  : macro path   "/e waves (macro path)."
--   3 = bottom : custom type  C_ChatInfo.PerformEmote("CHEER")
--   4 = left   : custom type  C_ChatInfo.SendChatMessage("...", "EMOTE")

local ADDON = ...
local N = 4
local DEAD_ZONE = 28

local function log(...)
	print("|cff66ccffJestSpike|r", ...)
end

-- Keybinding labels shown in Options -> Keybindings -> AddOns.
BINDING_HEADER_JESTSPIKE = "Jest (spike)"
_G["BINDING_NAME_CLICK JestSpikeButton:LeftButton"] = "Spike: hold to open wheel"
_G["BINDING_NAME_CLICK JestSpikeButton:repeat"] = "Spike: repeat last slice"

if InCombatLockdown() then
	log("|cffff5555WARNING|r loaded during combat lockdown; secure setup below may fail (R6). /reload out of combat.")
end

---------------------------------------------------------------------------
-- Secure frames
---------------------------------------------------------------------------
local header = CreateFrame("Frame", "JestSpikeHeader", UIParent, "SecureHandlerBaseTemplate")

-- Invisible protected geometry reference. Huge so GetMousePosition never returns nil.
local anchor = CreateFrame("Frame", "JestSpikeAnchor", UIParent, "SecureHandlerBaseTemplate")
anchor:SetSize(10000, 10000)
anchor:SetPoint("CENTER")
anchor:EnableMouse(false)

-- Small red dot at the anchor centre so you can see where $cursor put it (S4).
local marker = anchor:CreateTexture(nil, "OVERLAY")
marker:SetSize(8, 8)
marker:SetPoint("CENTER")
marker:SetColorTexture(1, 0.2, 0.2, 1)
marker:Hide()

local btn = CreateFrame("Button", "JestSpikeButton", UIParent, "SecureActionButtonTemplate")
btn:RegisterForClicks("AnyDown", "AnyUp")
btn:SetAttribute("useOnKeyDown", false) -- fire actions on key UP only (S3)

-- Macro-path slices.
btn:SetAttribute("type-slice1", "macro")
btn:SetAttribute("macrotext-slice1", "/dance")
btn:SetAttribute("type-slice2", "macro")
btn:SetAttribute("macrotext-slice2", "/e waves (macro path).")

-- Custom-type slices: SecureActionButton dispatches type "jestspike" to rawget(btn, "jestspike").
btn:SetAttribute("type-slice3", "jestspike")
btn:SetAttribute("type-slice4", "jestspike")
local customSlices = {
	slice3 = { kind = "emote", value = "CHEER" },
	slice4 = { kind = "text", value = "waves (custom-type path)." },
}

local function chatLockdown()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		return tostring(C_ChatInfo.InChatMessagingLockdown())
	end
	return "n/a"
end

function btn:jestspike(unit, button)
	local s = customSlices[button]
	if not s then
		log("[S6] no custom slice for", button)
		return
	end
	log("[S6] custom type fired:", button, s.kind, s.value, "| chatLockdown =", chatLockdown())
	if s.kind == "emote" then
		local fn = (C_ChatInfo and C_ChatInfo.PerformEmote) or DoEmote
		local ok, res = pcall(fn, s.value)
		log("[S6] PerformEmote ->", ok, tostring(res))
	else
		local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		local ok, err = pcall(fn, s.value, "EMOTE")
		log("[S6] SendChatMessage(EMOTE) ->", ok, tostring(err))
	end
end

---------------------------------------------------------------------------
-- Insecure notifications (called from the snippet via CallMethod)
---------------------------------------------------------------------------
local openX, openY

local function cursorUI()
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	return x / s, y / s
end

-- Same math as the snippet; Jest will keep this in UI/Geometry.lua.
local function sliceAt(dx, dy, n, dz)
	if dx * dx + dy * dy < dz * dz then return nil end
	local a = (90 - math.deg(math.atan2(dy, dx))) % 360
	local step = 360 / n
	return math.floor((a + step / 2) / step) % n + 1
end

function btn:OnSpikeOpen()
	openX, openY = cursorUI()
	marker:Show()
	log("[S4] open; mouselooking =", tostring(IsMouselooking()), "| combat =", tostring(InCombatLockdown()))
end

function btn:OnSpikeClose(secureIdx)
	marker:Hide()
	if openX then
		local x, y = cursorUI()
		local skinIdx = sliceAt(x - openX, y - openY, N, DEAD_ZONE)
		local match = (skinIdx == secureIdx) and "|cff55ff55match|r" or "|cffff5555MISMATCH|r"
		log("[R5] secure idx =", tostring(secureIdx), "| insecure idx =", tostring(skinIdx), match)
	end
end

---------------------------------------------------------------------------
-- Restricted snippet (runs in the secure sandbox, works in combat)
---------------------------------------------------------------------------
btn:SetAttribute("count", N)
btn:SetAttribute("deadzone", DEAD_ZONE)
SecureHandlerSetFrameRef(btn, "anchor", anchor)

local preBody = [=[
	local N = self:GetAttribute("count")
	local dz = self:GetAttribute("deadzone")

	-- Repeat-last binding (S5)
	if button == "repeat" then
		if down then return false end
		local last = self:GetAttribute("last")
		print("JestSpike [S5] repeat ->", last)
		return last or false
	end

	-- Esc while open (S5)
	if button == "cancel" then
		if down then return false end
		if self:GetAttribute("open") then
			self:SetAttribute("open", false)
			self:ClearBindings()
			self:CallMethod("OnSpikeClose", nil)
			print("JestSpike [S5] cancelled via Esc")
		end
		return false
	end

	-- Number keys while open (S5)
	local pick = string.match(button, "^pick(%d+)$")
	if pick then
		if down then return false end
		self:SetAttribute("open", false)
		self:ClearBindings()
		self:SetAttribute("last", "slice" .. pick)
		print("JestSpike [S5] number key picked slice", pick)
		self:CallMethod("OnSpikeClose", tonumber(pick))
		return "slice" .. pick
	end

	-- Main key
	local anchor = self:GetFrameRef("anchor")
	if down then
		anchor:ClearAllPoints()
		anchor:SetPoint("CENTER", "$cursor", "BOTTOMLEFT", 0, 0)
		self:SetAttribute("open", true)
		for i = 1, N do
			self:SetBindingClick(true, tostring(i), "JestSpikeButton", "pick" .. i)
		end
		self:SetBindingClick(true, "ESCAPE", "JestSpikeButton", "cancel")
		print("JestSpike [S2] down=true button=" .. tostring(button) .. " inCombat=" .. tostring(PlayerInCombat()))
		self:CallMethod("OnSpikeOpen")
		return false
	end

	print("JestSpike [S2] down=false")
	if not self:GetAttribute("open") then return false end
	self:SetAttribute("open", false)
	self:ClearBindings()

	local x, y = anchor:GetMousePosition()
	print("JestSpike [S4] GetMousePosition", x, y, "size", anchor:GetWidth(), anchor:GetHeight())
	if not x then
		self:CallMethod("OnSpikeClose", nil)
		return false
	end
	local dx = (x - 0.5) * anchor:GetWidth()
	local dy = (y - 0.5) * anchor:GetHeight()
	if dx * dx + dy * dy < dz * dz then
		print("JestSpike [S4] dead zone -> cancel")
		self:CallMethod("OnSpikeClose", nil)
		return false
	end
	local a = (90 - math.deg(math.atan2(dy, dx))) % 360
	local step = 360 / N
	local idx = math.floor((a + step / 2) / step) % N + 1
	print("JestSpike [S4] dx=" .. math.floor(dx) .. " dy=" .. math.floor(dy) .. " angle=" .. math.floor(a) .. " -> slice" .. idx)
	self:SetAttribute("last", "slice" .. idx)
	self:CallMethod("OnSpikeClose", idx)
	return "slice" .. idx
]=]

SecureHandlerWrapScript(btn, "OnClick", header, preBody)

---------------------------------------------------------------------------
-- S1 / S7 diagnostics
---------------------------------------------------------------------------
local DEFAULT_TOKENS = { "WAVE", "DANCE", "CHEER", "LAUGH", "BOW", "SALUTE", "APPLAUD", "THANK" }

local ICON_CANDIDATES = {
	WAVE = { "Interface\\Icons\\Ability_Warrior_RallyingCry", "Interface\\Icons\\Spell_Holy_Heal" },
	DANCE = { "Interface\\Icons\\INV_Misc_Drum_01", "Interface\\Icons\\Achievement_Halloween_Smiley_01" },
	CHEER = { "Interface\\Icons\\Achievement_Reputation_08", "Interface\\Icons\\Ability_Warrior_BattleShout" },
	LAUGH = { "Interface\\Icons\\Spell_Shadow_Charm", "Interface\\Icons\\INV_Misc_Toy_07" },
	BOW = { "Interface\\Icons\\Spell_Holy_PrayerOfHealing", "Interface\\Icons\\Achievement_Reputation_05" },
	SALUTE = { "Interface\\Icons\\Ability_Warrior_BattleShout", "Interface\\Icons\\INV_Misc_Bandana_03" },
	APPLAUD = { "Interface\\Icons\\Spell_Holy_SurgeOfLight", "Interface\\Icons\\Achievement_Reputation_06" },
	THANK = { "Interface\\Icons\\Achievement_Reputation_01", "Interface\\Icons\\INV_Misc_Gift_01" },
}

local function infoS1()
	local version, build, date, tocVersion = GetBuildInfo()
	log("[S1] GetBuildInfo:", version, build, date, "| interface =", tocVersion, "(TOC says 16001)")
	log("[S1] WOW_PROJECT_ID =", tostring(WOW_PROJECT_ID))
	for k, v in pairs(_G) do
		if type(k) == "string" and k:match("^WOW_PROJECT_") and type(v) == "number" then
			log("    ", k, "=", v)
		end
	end
	log("[S1] C_ChatInfo.PerformEmote exists:", tostring(C_ChatInfo and C_ChatInfo.PerformEmote ~= nil),
		"| InChatMessagingLockdown exists:", tostring(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown ~= nil))
end

local function dumpS7()
	local tokens, count = {}, 0
	for i = 1, 1500 do
		local t = _G["EMOTE" .. i .. "_TOKEN"]
		if t then
			tokens[t] = i
			count = count + 1
			if count <= 20 then
				log("    EMOTE" .. i .. "_TOKEN =", t, "/", tostring(_G["EMOTE" .. i .. "_CMD1"]))
			end
		end
	end
	log("[S7] emote tokens found:", count)
	for _, t in ipairs(DEFAULT_TOKENS) do
		local line = (tokens[t] and "|cff55ff55ok|r " or "|cffff5555MISSING|r ") .. t
		for _, path in ipairs(ICON_CANDIDATES[t]) do
			local id = GetFileIDFromPath and GetFileIDFromPath(path)
			line = line .. "  |T" .. path .. ":18|t" .. (id and tostring(id) or "nil")
		end
		log(line)
	end
end

SLASH_JESTSPIKE1 = "/jestspike"
SlashCmdList.JESTSPIKE = function(msg)
	msg = (msg or ""):lower()
	if msg == "info" then
		infoS1()
	elseif msg == "dump" then
		dumpS7()
	else
		log("/jestspike info  - S1 build/interface info")
		log("/jestspike dump  - S7 emote tokens + icon candidates")
		log("Bind keys in Options > Keybindings > AddOns > Jest (spike).")
		log("Slices: 1 top=/dance (macro), 2 right=/e (macro), 3 bottom=CHEER (custom), 4 left=/e (custom)")
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	log("loaded. Type /jestspike for help.")
	infoS1()
end)
