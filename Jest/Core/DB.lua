-- SavedVariables: JestDB holds account-wide profiles, JestCharDB the profile this character uses.
local _, ns = ...

local DB = {}
ns.DB = DB

local CURRENT_VERSION = 2
local ICON_PATH_MAX = 260

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do
		t[k] = deepCopy(x)
	end
	return t
end
DB.Copy = deepCopy

-- v1 -> v2: the "text" slice kind was dropped. Each becomes an equivalent "/e ..." macro that
-- keeps its old icon and label, so it looks and behaves the same.
local OLD_TEXT_ICON = "Interface\\Icons\\INV_Misc_Note_01"

local function migrateTextSlices(db)
	for _, profile in pairs(db.profiles) do
		local wheels = type(profile) == "table" and type(profile.wheels) == "table" and profile.wheels or {}
		for _, wheel in ipairs(wheels) do
			local slices = type(wheel) == "table" and type(wheel.slices) == "table" and wheel.slices or {}
			for _, s in ipairs(slices) do
				if type(s) == "table" and s.kind == "text" then
					local text = type(s.value) == "string" and s.value or ""
					s.kind = "macro"
					s.value = text ~= "" and ("/e " .. text):sub(1, ns.Slices.MACRO_MAX) or ""
					s.icon = s.icon or OLD_TEXT_ICON
					if not s.label and text ~= "" then
						s.label = #text > 18 and (text:sub(1, 17) .. "...") or text
					end
				end
			end
		end
	end
end

local function migrate(db)
	if db.version < 2 then migrateTextSlices(db) end
	db.version = CURRENT_VERSION
end

-- Saved variables are plain files that users and other addons can edit. Everything below makes
-- sure only well-formed data reaches the secure button (macro text, attributes) and the UI.
-- Action slices with invalid values are dropped rather than emptied: they can't be edited by
-- typing, so an empty one would only be confusing.

local function cleanSlice(s)
	if type(s) ~= "table" then return nil end
	local value
	if s.kind == "emote" or s.kind == "macro" then
		value = type(s.value) == "string" and s.value or ""
		if s.kind == "macro" then
			value = value:sub(1, ns.Slices.MACRO_MAX)
		end
	elseif ns.Actions.IsAction(s.kind) then
		if not ns.Actions.Valid(s.kind, s.value) then return nil end
		value = s.value
	else
		return nil
	end
	local icon = s.icon
	if not (type(icon) == "number" or (type(icon) == "string" and #icon <= ICON_PATH_MAX)) then
		icon = nil
	end
	local label = type(s.label) == "string" and s.label ~= "" and s.label:sub(1, ns.LABEL_MAX) or nil
	return { kind = s.kind, value = value, icon = icon, label = label }
end

local function validNumber(v, limits)
	return type(v) == "number" and v == v and v >= limits[1] and v <= limits[2] -- v == v rejects NaN
end

-- Trimmed and length-capped wheel name, or nil if nothing is left.
function DB.CleanWheelName(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("[\r\n|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	return text:sub(1, ns.WHEEL_NAME_MAX)
end

local function cleanWheel(wheel, position)
	if type(wheel) ~= "table" or type(wheel.slices) ~= "table" then return nil end
	local slices = {}
	for _, s in ipairs(wheel.slices) do
		local clean = cleanSlice(s)
		if clean and #slices < ns.MAX_SLICES then
			slices[#slices + 1] = clean
		end
	end
	if #slices == 0 then return nil end
	return { name = DB.CleanWheelName(wheel.name) or ("Wheel " .. position), slices = slices }
end

-- Returns a clean copy of `p`, or nil if nothing usable is left.
local function cleanProfile(p)
	if type(p) ~= "table" then return nil end
	local defaults = ns.Defaults.profile
	local out = {}
	for key, limits in pairs(ns.Limits) do
		out[key] = validNumber(p[key], limits) and p[key] or defaults[key]
	end
	for _, key in ipairs({ "sounds", "rememberWheel" }) do
		if type(p[key]) == "boolean" then
			out[key] = p[key]
		else
			out[key] = defaults[key]
		end
	end

	-- Wheels left with no usable slices are dropped; with no wheels left, start from the defaults.
	out.wheels = {}
	if type(p.wheels) == "table" then
		for _, wheel in ipairs(p.wheels) do
			local clean = cleanWheel(wheel, #out.wheels + 1)
			if clean and #out.wheels < ns.MAX_WHEELS then
				out.wheels[#out.wheels + 1] = clean
			end
		end
	end
	if #out.wheels == 0 then
		out.wheels = deepCopy(defaults.wheels)
	end
	return out
end

---------------------------------------------------------------------------
-- Profiles: named sets of wheels and appearance settings, shared across the account. Each
-- character uses one.
---------------------------------------------------------------------------
DB.DEFAULT_PROFILE = "Default"

local editIndex = 1 -- see DB.EditIndex below

-- This character's GUID, the key in the account-wide JestDB.chars, or nil when the game can't
-- say yet. Not "Name - Realm": on Forever, GetRealmName() is the same for characters on
-- different realms, so same-named characters (e.g. one per realm) collided.
function DB.CharacterKey()
	local guid = UnitGUID and UnitGUID("player")
	if type(guid) == "string" and guid:match("^Player%-") then
		return guid
	end
end

-- This character's name, or nil when the game can't say yet.
function DB.CharacterName()
	local name = UnitName and UnitName("player")
	if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT or name == "Unknown" then
		return nil
	end
	return name
end

-- An unused profile name based on `base`: "Oxe", then "Oxe (2)", "Oxe (3)"...
local function unusedProfileName(base)
	base = base:sub(1, ns.PROFILE_NAME_MAX - 4)
	if not DB.FindProfile(base) then return base end
	local n = 2
	while DB.FindProfile(("%s (%d)"):format(base, n)) do n = n + 1 end
	return ("%s (%d)"):format(base, n)
end

-- Make `name` this character's profile.
local function setCurrent(name)
	JestCharDB.profile = name
	local key = DB.CharacterKey()
	if key then JestDB.chars[key] = name end
	editIndex = 1
end

-- Trimmed, length-capped profile name without chat markup, or nil if nothing is left.
function DB.CleanProfileName(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("[\r\n|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	return text:sub(1, ns.PROFILE_NAME_MAX)
end

-- The existing profile called `name`, ignoring case (so "default" finds "Default").
function DB.FindProfile(name)
	if type(name) ~= "string" then return nil end
	if JestDB.profiles[name] then return name end
	local lower = name:lower()
	for existing in pairs(JestDB.profiles) do
		if existing:lower() == lower then return existing end
	end
end

-- Checks a name for a new or renamed profile. Returns the clean name, or nil and a message.
local function checkNewName(text, except)
	local name = DB.CleanProfileName(text)
	if not name then return nil, "Type a name for the profile." end
	local taken = DB.FindProfile(name)
	if taken and taken ~= except then
		return nil, ("There's already a profile called \"%s\"."):format(taken)
	end
	return name
end

-- Profile names, sorted alphabetically.
function DB.ProfileNames()
	local names = {}
	for name in pairs(JestDB.profiles) do names[#names + 1] = name end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	return names
end

-- How many characters (that Jest has seen) use profile `name`.
function DB.ProfileUsers(name)
	local n = 0
	for _, used in pairs(JestDB.chars) do
		if used == name then n = n + 1 end
	end
	return n
end

-- Switch this character to an existing profile.
function DB.SetProfile(name)
	local found = DB.FindProfile(name)
	if not found then return nil, ("There's no profile called \"%s\"."):format(tostring(name)) end
	setCurrent(found)
	return found
end

-- Create a profile with the default wheel and switch to it. Returns its name, or nil and a message.
function DB.NewProfile(text)
	local name, err = checkNewName(text)
	if not name then return nil, err end
	JestDB.profiles[name] = deepCopy(ns.Defaults.profile)
	setCurrent(name)
	return name
end

-- Replace this character's profile with a copy of profile `from`. Returns the replaced contents
-- (for undo), or nil and a message.
function DB.CopyProfile(from)
	local source = DB.FindProfile(from)
	if not source then return nil, ("There's no profile called \"%s\"."):format(tostring(from)) end
	if source == DB.ProfileName() then return nil, "That's the profile you're using." end
	local previous = JestDB.profiles[DB.ProfileName()]
	JestDB.profiles[DB.ProfileName()] = deepCopy(JestDB.profiles[source])
	editIndex = 1
	return previous
end

-- Put a profile's earlier contents back (undo of a copy or reset).
function DB.RestoreProfile(name, contents)
	if not JestDB.profiles[name] then return false end
	JestDB.profiles[name] = contents
	editIndex = 1
	return true
end

-- Rename this character's profile; every character using it follows.
function DB.RenameProfile(text)
	local old = DB.ProfileName()
	local name, err = checkNewName(text, old)
	if not name then return nil, err end
	if name == old then return name end
	JestDB.profiles[name], JestDB.profiles[old] = JestDB.profiles[old], nil
	for key, used in pairs(JestDB.chars) do
		if used == old then JestDB.chars[key] = name end
	end
	JestCharDB.profile = name
	return name
end

-- Delete a profile. Other characters that used it get a fresh profile next time they log in.
-- Deleting this character's own profile moves it to a profile named after it if there is
-- one, otherwise to the first remaining profile (removed.switchedTo). Returns what's needed to
-- undo it, or nil and a message.
function DB.DeleteProfile(name)
	local found = DB.FindProfile(name)
	if not found then return nil, ("There's no profile called \"%s\"."):format(tostring(name)) end
	if #DB.ProfileNames() <= 1 then return nil, "You need at least one profile." end
	local removed = { name = found, contents = JestDB.profiles[found], chars = {} }
	for key, used in pairs(JestDB.chars) do
		if used == found then
			removed.chars[#removed.chars + 1] = key
			JestDB.chars[key] = nil
		end
	end
	JestDB.profiles[found] = nil
	if found == DB.ProfileName() then
		local own = DB.CharacterName() and DB.FindProfile(DB.CharacterName())
		local nextName = own or DB.ProfileNames()[1]
		setCurrent(nextName)
		removed.switchedTo = nextName
	end
	return removed
end

-- Undo a delete; a character that was moved off the profile moves back to it.
function DB.UndeleteProfile(removed)
	if JestDB.profiles[removed.name] then return false end
	JestDB.profiles[removed.name] = removed.contents
	for _, key in ipairs(removed.chars) do
		if not JestDB.chars[key] then JestDB.chars[key] = removed.name end
	end
	if removed.switchedTo and DB.ProfileName() == removed.switchedTo then
		setCurrent(removed.name)
	end
	return true
end

function DB.Init()
	if type(JestDB) ~= "table" then JestDB = {} end
	if type(JestCharDB) ~= "table" then JestCharDB = {} end
	if type(JestDB.profiles) ~= "table" then JestDB.profiles = {} end
	if type(JestDB.version) ~= "number" then JestDB.version = CURRENT_VERSION end
	migrate(JestDB)

	for name, profile in pairs(JestDB.profiles) do
		JestDB.profiles[name] = type(name) == "string" and cleanProfile(profile) or nil
	end

	-- The wheel this character last had showing, for "Reopen on last wheel used" after a reload.
	local last = JestCharDB.lastWheel
	if not (type(last) == "number" and last == math.floor(last) and last >= 1 and last <= ns.MAX_WHEELS) then
		JestCharDB.lastWheel = nil
	end

	-- Minimap button position and visibility.
	if type(JestDB.minimap) ~= "table" then JestDB.minimap = {} end
	local minimap = JestDB.minimap
	if not validNumber(minimap.angle, { 0, 360 }) then minimap.angle = ns.Defaults.minimap.angle end
	if type(minimap.hide) ~= "boolean" then minimap.hide = ns.Defaults.minimap.hide end

	-- Which character uses which profile, account-wide, so renaming a profile can follow it for
	-- every character, not just this one.
	-- Keys are character GUIDs; entries keyed "Name - Realm" (before v0.6.1) are dropped, since
	-- same-named characters shared one. Each character re-adds itself when it logs in.
	if type(JestDB.chars) ~= "table" then JestDB.chars = {} end
	for key, name in pairs(JestDB.chars) do
		if type(key) ~= "string" or not key:match("^Player%-") or type(name) ~= "string"
			or not JestDB.profiles[name] then
			JestDB.chars[key] = nil
		end
	end

	-- This character's own saved profile comes first: it's per-character by nature. The
	-- account-wide list only fills in when that profile is gone, e.g. renamed on another
	-- character (the list follows renames).
	local key = DB.CharacterKey()
	local name = JestCharDB.profile
	if type(name) ~= "string" or not JestDB.profiles[name] then
		name = key and JestDB.chars[key]
	end
	if type(name) ~= "string" or not JestDB.profiles[name] then
		-- A character Jest hasn't seen before starts on a fresh profile of its own, named after it.
		-- (Characters from before profiles keep the shared "Default" they were already using.)
		local charName = DB.CharacterName()
		if charName then
			name = unusedProfileName(charName)
		else
			name = DB.DEFAULT_PROFILE
		end
		if not JestDB.profiles[name] then
			JestDB.profiles[name] = deepCopy(ns.Defaults.profile)
		end
	end
	setCurrent(name)
end

-- Once logged in: record this character in the account-wide list, in case the game couldn't
-- say who it was when the addon loaded.
function DB.RecordCharacter()
	local key = DB.CharacterKey()
	if key and JestCharDB and JestCharDB.profile then
		JestDB.chars[key] = JestCharDB.profile
	end
end

function DB.Profile()
	return JestDB.profiles[JestCharDB.profile]
end

function DB.ProfileName()
	return JestCharDB.profile
end

-- A profile has 1..MAX_WHEELS wheels. Scrolling while the wheel is open moves between them.
function DB.Wheels()
	return DB.Profile().wheels
end

-- The wheel the options panel and slash commands are editing (editIndex, declared with the
-- profile code above). Not saved: each session, and each profile switch, starts on the first wheel.
function DB.EditIndex()
	editIndex = math.max(1, math.min(editIndex, #DB.Wheels()))
	return editIndex
end

function DB.SetEditIndex(i)
	editIndex = i
	return DB.EditIndex()
end

-- Wheel i, or the wheel being edited.
function DB.Wheel(i)
	return DB.Wheels()[i or DB.EditIndex()]
end

function DB.NewWheel(position)
	local slices = {}
	for i = 1, ns.NEW_WHEEL_SLICES do
		slices[i] = { kind = "emote", value = "" }
	end
	return { name = "Wheel " .. position, slices = slices }
end

-- Appends a new wheel. Returns its index, or nil and a message when there's no room.
function DB.AddWheel(name)
	local wheels = DB.Wheels()
	if #wheels >= ns.MAX_WHEELS then
		return nil, ("You can have at most %d wheels."):format(ns.MAX_WHEELS)
	end
	local wheel = DB.NewWheel(#wheels + 1)
	wheel.name = DB.CleanWheelName(name) or wheel.name
	wheels[#wheels + 1] = wheel
	return #wheels
end

-- Removes wheel i and returns it, or nil and a message when it's the only one.
function DB.RemoveWheel(i)
	local wheels = DB.Wheels()
	if #wheels <= 1 then
		return nil, "You need at least one wheel."
	end
	local editing = wheels[DB.EditIndex()]
	local removed = table.remove(wheels, i)
	DB.SetEditIndex(DB.IndexOfWheel(editing) or i)
	return removed
end

-- Puts a removed wheel back at position i (undo). Returns its index, or nil when full.
function DB.InsertWheel(i, wheel)
	local wheels = DB.Wheels()
	if #wheels >= ns.MAX_WHEELS then return nil end
	i = math.max(1, math.min(i, #wheels + 1))
	table.insert(wheels, i, wheel)
	return i
end

-- Moves wheel `from` to position `to`. The edited wheel stays selected wherever it ends up.
function DB.MoveWheel(from, to)
	local wheels = DB.Wheels()
	if from == to or not wheels[from] or to < 1 or to > #wheels then return false end
	local editing = wheels[DB.EditIndex()]
	table.insert(wheels, to, table.remove(wheels, from))
	DB.SetEditIndex(DB.IndexOfWheel(editing) or to)
	return true
end

function DB.IndexOfWheel(wheel)
	for i, w in ipairs(DB.Wheels()) do
		if w == wheel then return i end
	end
end

-- Back to the default wheel and settings. Returns the replaced contents (for undo).
function DB.ResetProfile()
	local previous = JestDB.profiles[JestCharDB.profile]
	JestDB.profiles[JestCharDB.profile] = deepCopy(ns.Defaults.profile)
	editIndex = 1
	return previous
end
