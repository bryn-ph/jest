-- SavedVariables: JestDB (account-wide profiles) + JestCharDB (which profile this character uses).
local _, ns = ...

local DB = {}
ns.DB = DB

local CURRENT_VERSION = 1

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do
		t[k] = deepCopy(x)
	end
	return t
end
DB.Copy = deepCopy

-- Fill missing top-level profile settings from defaults. Wheels/slices are user data and are
-- only seeded when absent, never merged index-by-index (that would resurrect deleted slices).
local function fillDefaults(profile, defaults)
	for k, v in pairs(defaults) do
		if profile[k] == nil then
			profile[k] = deepCopy(v)
		end
	end
end

local function migrate(db)
	-- Future schema changes go here, e.g. `if db.version < 2 then ... end`.
	db.version = CURRENT_VERSION
end

function DB.Init()
	JestDB = JestDB or {}
	JestCharDB = JestCharDB or {}
	JestDB.version = JestDB.version or CURRENT_VERSION
	JestDB.profiles = JestDB.profiles or {}
	migrate(JestDB)

	JestCharDB.profile = JestCharDB.profile or "Default"
	if not JestDB.profiles[JestCharDB.profile] then
		JestDB.profiles[JestCharDB.profile] = deepCopy(ns.Defaults.profile)
	end
	for _, profile in pairs(JestDB.profiles) do
		fillDefaults(profile, ns.Defaults.profile)
	end
end

function DB.Profile()
	return JestDB.profiles[JestCharDB.profile]
end

function DB.ProfileName()
	return JestCharDB.profile
end

-- MVP has a single wheel per profile; multiple wheels are a stretch goal.
function DB.Wheel()
	return DB.Profile().wheels[1]
end

function DB.ResetProfile()
	JestDB.profiles[JestCharDB.profile] = deepCopy(ns.Defaults.profile)
end
