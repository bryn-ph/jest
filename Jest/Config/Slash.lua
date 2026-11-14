-- /jest (alias /ew). With no arguments it opens the options panel; /jest help lists commands.
local _, ns = ...

local Print, Escape = ns.Print, ns.Escape
local commands = {}
local order = {}

local function add(name, usage, fn)
	commands[name] = { usage = usage, fn = fn }
	table.insert(order, name)
end

local function slices()
	return ns.DB.Wheel().slices
end

local function parseIndex(text, allowAppend)
	local i = tonumber(text)
	local count = #slices()
	local max = allowAppend and math.min(count + 1, ns.MAX_SLICES) or count
	if not i or i < 1 or i > max or i ~= math.floor(i) then
		Print(("Slice number must be 1-%d."):format(max))
		return nil
	end
	return i
end

local function describe(i, s)
	if not ns.Slices.HasAction(s) then
		return ("%d. |cff888888(empty)|r"):format(i)
	end
	return ("%d. |T%s:16|t %s |cff888888[%s] %s|r"):format(
		i, Escape(ns.Slices.Icon(s)), Escape(ns.Slices.Label(s)), s.kind, Escape(s.value))
end

local KIND_ALIASES = {
	emote = "emote", e = "emote", macro = "macro", m = "macro",
	item = "item", i = "item", spell = "spell", s = "spell", toy = "toy",
}

add("list", "list - show the wheel's slices", function()
	Print(("Profile '%s':"):format(Escape(ns.DB.ProfileName())))
	for i, s in ipairs(slices()) do
		Print(describe(i, s))
	end
end)

add("set", "set <n> emote <name> || macro <text> || item <id> || spell <id> || toy <id> - set a slice (\\n for new lines; /e <text> for a custom emote line)", function(rest)
	local nText, kindText, value = rest:match("^(%S+)%s+(%S+)%s+(.+)$")
	if not nText then
		Print("Usage: /jest " .. commands.set.usage)
		return
	end
	local i = parseIndex(nText, true)
	if not i then return end
	local kind = KIND_ALIASES[kindText:lower()]
	if not kind then
		Print("Kind must be emote, macro, item, spell or toy. For a custom emote line, use: macro /e <text>")
		return
	end
	if kind == "macro" then
		value = value:gsub("\\n", "\n")
	end
	local valid, err = ns.Slices.Validate(kind, value)
	if not valid then
		Print(err)
		return
	end

	local list = slices()
	local old = list[i] or {}
	list[i] = { kind = kind, value = valid, icon = old.icon, label = old.label }
	Print("Set " .. describe(i, list[i]))
	ns.Changed()
end)

add("remove", "remove <n> - delete a slice", function(rest)
	local i = parseIndex(rest)
	if not i then return end
	if #slices() <= 1 then
		Print("The wheel needs at least one slice.")
		return
	end
	table.remove(slices(), i)
	Print("Removed slice " .. i .. ".")
	ns.Changed()
end)

add("move", "move <from> <to> - move a slice to another position", function(rest)
	local a, b = rest:match("^(%S+)%s+(%S+)$")
	local from, to = parseIndex(a or ""), parseIndex(b or "")
	if not (from and to) then return end
	local list = slices()
	table.insert(list, to, table.remove(list, from))
	Print(("Moved slice %d to %d."):format(from, to))
	ns.Changed()
end)

add("icon", "icon <n> <file ID || icon name || path || reset>", function(rest)
	local nText, value = rest:match("^(%S+)%s+(.+)$")
	local i = parseIndex(nText or "")
	if not i or not value then return end
	local s = slices()[i]
	if value:lower() == "reset" then
		s.icon = nil
	else
		local icon = ns.Slices.ParseIcon(value)
		if not icon then
			Print("That isn't a valid icon name, path or file ID.")
			return
		end
		s.icon = icon
	end
	Print("Icon " .. describe(i, s))
	ns.Changed()
end)

add("label", "label <n> <text || reset>", function(rest)
	local nText, value = rest:match("^(%S+)%s+(.+)$")
	local i = parseIndex(nText or "")
	if not i or not value then return end
	local s = slices()[i]
	s.label = (value:lower() ~= "reset") and value:sub(1, ns.LABEL_MAX) or nil
	Print("Label " .. describe(i, s))
	ns.Changed()
end)

add("test", "test <n> - perform an emote slice now", function(rest)
	local i = parseIndex(rest)
	if i and not ns.SecureWheel.TestEmote(i) then
		Print("Only emote slices can be tested from chat; macros fire from the wheel.")
	end
end)

add("emotes", "emotes [filter] - list emote names", function(rest)
	local filter = rest ~= "" and rest:upper() or nil
	local shown, total = 0, 0
	local names = {}
	for _, e in ipairs(ns.Emotes.All()) do
		if not filter or e.token:find(filter, 1, true) then
			total = total + 1
			if shown < 60 then
				shown = shown + 1
				names[#names + 1] = e.token
			end
		end
	end
	Print(("%d emote(s)%s:"):format(total, filter and (" matching '" .. Escape(rest) .. "'") or ""))
	for k = 1, #names, 10 do
		Print("  " .. table.concat(names, ", ", k, math.min(k + 9, #names)))
	end
	if total > shown then Print("  ...narrow it with a filter.") end
end)

local function numberSetting(key)
	local limits = ns.Limits[key]
	return function(rest)
		local profile = ns.DB.Profile()
		if rest == "" then
			Print(("%s = %s"):format(key, tostring(profile[key])))
			return
		end
		local v = tonumber(rest)
		if not v or v ~= v or v < limits[1] or v > limits[2] then -- v ~= v catches NaN
			Print(("%s must be a number from %s to %s."):format(key, limits[1], limits[2]))
			return
		end
		profile[key] = v
		Print(("%s set to %s."):format(key, v))
		ns.Changed()
	end
end

add("radius", "radius <40-300> - distance from the centre to the icons", numberSetting("radius"))
add("deadzone", "deadzone <8-100> - size of the cancel zone in the centre", numberSetting("deadZone"))
add("scale", "scale <0.5-2> - overall wheel size", numberSetting("scale"))

add("sound", "sound on||off", function(rest)
	local profile = ns.DB.Profile()
	if rest == "on" or rest == "off" then
		profile.sounds = rest == "on"
	end
	Print("Sounds " .. (profile.sounds and "on" or "off") .. ".")
end)

add("reset", "reset yes - restore the default wheel for this profile", function(rest)
	if rest ~= "yes" then
		Print("This replaces every slice and setting in this profile. Type |cffffff00/jest reset yes|r to confirm.")
		return
	end
	ns.DB.ResetProfile()
	Print("Profile reset to defaults.")
	ns.Changed()
end)

add("debug", "debug - toggle debug messages", function()
	ns.debug = not ns.debug
	Print("Debug " .. (ns.debug and "on" or "off") .. ".")
end)

local function help()
	Print("|cffffff00/jest|r opens the options (Options > AddOns > Jest). Commands, also available as /ew:")
	for _, name in ipairs(order) do
		Print("  |cffffff00" .. commands[name].usage .. "|r")
	end
end

SLASH_JEST1 = "/jest"
SLASH_JEST2 = "/ew"
SlashCmdList.JEST = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		ns.Panel.Open()
		return
	end
	local entry = commands[cmd]
	if entry then
		entry.fn(rest or "")
	else
		help()
	end
end
