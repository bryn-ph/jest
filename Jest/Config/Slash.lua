-- /jest and /ew slash commands. `/jest` alone opens the options panel; `/jest help` lists commands.
local _, ns = ...

local Print = ns.Print
local commands = {}
local order = {}

local function add(name, usage, fn)
	commands[name] = { usage = usage, fn = fn }
	table.insert(order, name)
end

local function slices()
	return ns.DB.Wheel().slices
end

local function changed()
	ns.Changed()
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
	local icon = ns.Slices.Icon(s)
	return ("%d. |T%s:16|t %s |cff888888[%s] %s|r"):format(i, tostring(icon), ns.Slices.Label(s), s.kind, s.value)
end

local KIND_ALIASES = { emote = "emote", e = "emote", text = "text", t = "text", macro = "macro", m = "macro" }

add("list", "list - show the wheel's slices", function()
	Print(("Profile '%s':"):format(ns.DB.ProfileName()))
	for i, s in ipairs(slices()) do
		Print(describe(i, s))
	end
end)

add("set", "set <n> emote <TOKEN||/cmd> || text <message> || macro <macro text, \\n for new lines>", function(rest)
	local nText, kindText, value = rest:match("^(%S+)%s+(%S+)%s+(.+)$")
	if not nText then
		Print("Usage: /jest " .. commands.set.usage)
		return
	end
	local i = parseIndex(nText, true)
	if not i then return end
	local kind = KIND_ALIASES[kindText:lower()]
	if not kind then
		Print("Kind must be emote, text or macro.")
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
	-- Custom icon/label overrides are kept; reset them with `icon <n> reset` / `label <n> reset`.
	list[i] = { kind = kind, value = valid, icon = old.icon, label = old.label }
	Print("Set " .. describe(i, list[i]))
	changed()
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
	changed()
end)

add("move", "move <from> <to> - reorder slices", function(rest)
	local a, b = rest:match("^(%S+)%s+(%S+)$")
	local from, to = parseIndex(a or ""), parseIndex(b or "")
	if not (from and to) then return end
	local list = slices()
	table.insert(list, to, table.remove(list, from))
	Print(("Moved slice %d to %d."):format(from, to))
	changed()
end)

add("icon", "icon <n> <fileID || icon name || path || reset>", function(rest)
	local nText, value = rest:match("^(%S+)%s+(.+)$")
	local i = parseIndex(nText or "")
	if not i or not value then return end
	local s = slices()[i]
	if value:lower() == "reset" then
		s.icon = nil
	else
		s.icon = ns.Slices.ParseIcon(value)
	end
	Print("Icon " .. describe(i, s))
	changed()
end)

add("label", "label <n> <text || reset>", function(rest)
	local nText, value = rest:match("^(%S+)%s+(.+)$")
	local i = parseIndex(nText or "")
	if not i or not value then return end
	local s = slices()[i]
	s.label = (value:lower() ~= "reset") and value or nil
	Print("Label " .. describe(i, s))
	changed()
end)

add("test", "test <n> - fire an emote/text slice now (macro slices need the wheel)", function(rest)
	local i = parseIndex(rest)
	if i and not ns.SecureWheel.TestChat(i) then
		Print("Only emote/text slices can be tested from chat.")
	end
end)

add("emotes", "emotes [filter] - list emote tokens", function(rest)
	local filter = rest ~= "" and rest:upper() or nil
	local shown, total = 0, 0
	local line = {}
	for _, e in ipairs(ns.Emotes.All()) do
		if not filter or e.token:find(filter, 1, true) then
			total = total + 1
			if shown < 60 then
				shown = shown + 1
				table.insert(line, e.token)
			end
		end
	end
	Print(("%d emote(s)%s:"):format(total, filter and (" matching '" .. rest .. "'") or ""))
	for k = 1, #line, 10 do
		Print("  " .. table.concat(line, ", ", k, math.min(k + 9, #line)))
	end
	if total > shown then Print("  ...narrow it with a filter.") end
end)

local function numberSetting(key, minV, maxV)
	return function(rest)
		local v = tonumber(rest)
		local profile = ns.DB.Profile()
		if not v then
			Print(("%s = %s"):format(key, tostring(profile[key])))
			return
		end
		if v < minV or v > maxV then
			Print(("%s must be between %s and %s."):format(key, minV, maxV))
			return
		end
		profile[key] = v
		Print(("%s set to %s."):format(key, v))
		changed()
	end
end

add("radius", "radius <40-300> - icon ring size", numberSetting("radius", 40, 300))
add("deadzone", "deadzone <8-100> - cancel zone radius", numberSetting("deadZone", 8, 100))
add("scale", "scale <0.5-2> - overall wheel scale", numberSetting("scale", 0.5, 2))

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
	changed()
end)

add("debug", "debug - toggle debug output (prints secure vs skin slice on every fire)", function()
	ns.debug = not ns.debug
	Print("Debug " .. (ns.debug and "on" or "off") .. ".")
end)

local function help()
	Print("|cffffff00/jest|r opens the options panel (Options > AddOns > Jest). Commands (/jest or /ew):")
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
