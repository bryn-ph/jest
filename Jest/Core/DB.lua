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

local function cleanSlice(s)
	if type(s) ~= "table" or (s.kind ~= "emote" and s.kind ~= "macro") then
		return nil
	end
	local value = type(s.value) == "string" and s.value or ""
	if s.kind == "macro" then
		value = value:sub(1, ns.Slices.MACRO_MAX)
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

-- Returns a clean copy of `p`, or nil if nothing usable is left.
local function cleanProfile(p)
	if type(p) ~= "table" then return nil end
	local defaults = ns.Defaults.profile
	local out = {}
	for key, limits in pairs(ns.Limits) do
		out[key] = validNumber(p[key], limits) and p[key] or defaults[key]
	end
	if type(p.sounds) == "boolean" then
		out.sounds = p.sounds
	else
		out.sounds = defaults.sounds
	end

	local wheel = type(p.wheels) == "table" and p.wheels[1]
	local slices = {}
	if type(wheel) == "table" and type(wheel.slices) == "table" then
		for _, s in ipairs(wheel.slices) do
			local clean = cleanSlice(s)
			if clean and #slices < ns.MAX_SLICES then
				slices[#slices + 1] = clean
			end
		end
	end
	if #slices == 0 then
		slices = deepCopy(defaults.wheels[1].slices)
	end
	local name = type(wheel) == "table" and type(wheel.name) == "string" and wheel.name or defaults.wheels[1].name
	out.wheels = { { name = name, slices = slices } }
	return out
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

	if type(JestCharDB.profile) ~= "string" then
		JestCharDB.profile = "Default"
	end
	if not JestDB.profiles[JestCharDB.profile] then
		JestDB.profiles[JestCharDB.profile] = deepCopy(ns.Defaults.profile)
	end
end

function DB.Profile()
	return JestDB.profiles[JestCharDB.profile]
end

function DB.ProfileName()
	return JestCharDB.profile
end

-- One wheel per profile for now; the data model allows more later.
function DB.Wheel()
	return DB.Profile().wheels[1]
end

function DB.ResetProfile()
	JestDB.profiles[JestCharDB.profile] = deepCopy(ns.Defaults.profile)
end
