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

-- "Emotes" or, with several wheels, "wheel 2 'Potions'".
local function wheelTitle(i)
	i = i or ns.DB.EditIndex()
	local name = Escape(ns.DB.Wheel(i).name)
	if #ns.DB.Wheels() == 1 then return "'" .. name .. "'" end
	return ("wheel %d '%s'"):format(i, name)
end

add("list", "list - show the slices of the wheel being edited", function()
	Print(("Profile '%s', %s:"):format(Escape(ns.DB.ProfileName()), wheelTitle()))
	for i, s in ipairs(slices()) do
		Print(describe(i, s))
	end
end)

local function listWheels()
	local editing = ns.DB.EditIndex()
	for i, wheel in ipairs(ns.DB.Wheels()) do
		Print(("%s%d. %s |cff888888(%d slices)|r"):format(i == editing and "> " or "  ", i, Escape(wheel.name), #wheel.slices))
	end
	Print("Commands edit the wheel marked >. Scroll the mouse wheel while the wheel is open to switch.")
end

add("wheel", "wheel [<n> || add [name] || rename <name> || remove <n> yes] - list wheels, pick the one to edit, or add/rename/remove one", function(rest)
	local sub, arg = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "" then
		listWheels()
	elseif tonumber(sub) then
		local i = tonumber(sub)
		if not ns.DB.Wheel(i) or i ~= math.floor(i) then
			Print(("Wheel number must be 1-%d."):format(#ns.DB.Wheels()))
			return
		end
		ns.DB.SetEditIndex(i)
		Print("Now editing " .. wheelTitle(i) .. ".")
		ns.Panel.Refresh() -- nothing to re-apply; just show it if the options are open
	elseif sub == "add" then
		local i, err = ns.DB.AddWheel(arg)
		if not i then
			Print(err)
			return
		end
		ns.DB.SetEditIndex(i)
		Print(("Added %s with %d empty slices. Fill them with /jest set, or in the options."):format(wheelTitle(i), #ns.DB.Wheel(i).slices))
		ns.Changed()
	elseif sub == "rename" then
		local name = ns.DB.CleanWheelName(arg)
		if not name then
			Print("Usage: /jest wheel rename <name>")
			return
		end
		ns.DB.Wheel().name = name
		Print("Renamed to " .. wheelTitle() .. ".")
		ns.Changed()
	elseif sub == "remove" then
		local nText, confirm = arg:match("^(%S+)%s*(%S*)$")
		local i = tonumber(nText or "")
		if not (i and ns.DB.Wheel(i)) then
			Print(("Usage: /jest wheel remove <1-%d> yes"):format(#ns.DB.Wheels()))
			return
		end
		if confirm ~= "yes" then
			Print(("This deletes %s and its slices. Type |cffffff00/jest wheel remove %d yes|r to confirm."):format(wheelTitle(i), i))
			return
		end
		local title = wheelTitle(i)
		local removed, err = ns.DB.RemoveWheel(i)
		if not removed then
			Print(err)
			return
		end
		Print("Removed " .. title .. ".")
		ns.Changed()
	else
		Print("Usage: /jest " .. commands.wheel.usage)
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
	if i and not ns.SecureWheel.TestEmote(ns.DB.EditIndex(), i) then
		Print("Only emote slices can be tested from chat; other slices fire from the wheel.")
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

add("minimap", "minimap [on||off] - show or hide the minimap button (toggles with no argument)", function(rest)
	local show
	if rest == "on" or rest == "off" then
		show = rest == "on"
	else
		show = not ns.MinimapButton.IsShown()
	end
	ns.MinimapButton.SetShown(show)
	Print("Minimap button " .. (show and "shown" or "hidden") .. ".")
end)

add("reset", "reset yes - restore the default wheel for this profile", function(rest)
	if rest ~= "yes" then
		Print("This replaces every wheel, slice and setting in this profile. Type |cffffff00/jest reset yes|r to confirm.")
		return
	end
	ns.DB.ResetProfile()
	Print("Profile reset to defaults.")
	ns.Changed()
end)

local function listProfiles()
	local current = ns.DB.ProfileName()
	for _, name in ipairs(ns.DB.ProfileNames()) do
		local users = ns.DB.ProfileUsers(name)
		Print(("%s%s |cff888888(%d character%s)|r"):format(name == current and "> " or "  ", Escape(name), users, users == 1 and "" or "s"))
	end
	Print("This character uses the profile marked >.")
end

add("profile", "profile [<name> || new <name> || copy <name> || rename <name> || delete <name> yes] - list profiles, switch, or manage them", function(rest)
	local sub, arg = rest:match("^(%S*)%s*(.-)$")
	local verb = (sub or ""):lower()
	if verb == "" then
		listProfiles()
		return
	end
	local name, err
	if verb == "new" then
		name, err = ns.DB.NewProfile(arg)
		if name then Print(("Switched to new profile '%s'."):format(Escape(name))) end
	elseif verb == "copy" then
		local previous
		previous, err = ns.DB.CopyProfile(arg)
		if previous then Print(("Copied '%s' into '%s'."):format(Escape(arg), Escape(ns.DB.ProfileName()))) end
		name = previous and true
	elseif verb == "rename" then
		name, err = ns.DB.RenameProfile(arg)
		if name then Print(("Renamed to '%s'."):format(Escape(name))) end
	elseif verb == "delete" then
		local target, confirm = arg:match("^(.-)%s+(yes)$")
		if not target then
			Print(("This deletes the profile '%s'. Type |cffffff00/jest profile delete %s yes|r to confirm."):format(Escape(arg), Escape(arg)))
			return
		end
		local removed
		removed, err = ns.DB.DeleteProfile(target)
		if removed then Print(("Deleted '%s'."):format(Escape(removed.name))) end
		name = removed and true
	else
		name, err = ns.DB.SetProfile(rest)
		if name then Print(("Using profile '%s'."):format(Escape(name))) end
	end
	if not name then
		Print(Escape(err))
		return
	end
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
		ns.Panel.Toggle()
		return
	end
	local entry = commands[cmd]
	if entry then
		entry.fn(rest or "")
	else
		help()
	end
end
