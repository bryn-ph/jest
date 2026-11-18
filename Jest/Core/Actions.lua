-- Action slices: things dragged onto the wheel from bags, the spellbook, collections and so on.
-- Each kind knows how to describe itself (icon, name, count) and how the secure button fires it.
local _, ns = ...

local Actions = {}
ns.Actions = Actions

local NAME_MAX = 64

local function positiveInt(v)
	return type(v) == "number" and v > 0 and v == math.floor(v) and v < 2 ^ 31
end

local function shortString(v)
	return type(v) == "string" and v ~= "" and #v <= NAME_MAX
end

local function itemCount(itemID)
	if C_Item and C_Item.GetItemCount then
		return C_Item.GetItemCount(itemID, false, true) -- includeUses: charges count too
	elseif GetItemCount then
		return GetItemCount(itemID, false, true)
	end
end

local function itemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(itemID) -- ITEM_DATA_LOAD_RESULT refreshes the UI
	end
	return name
end

local function itemIcon(itemID)
	return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
end

local function spellInfo(spellID)
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
	if info then return info.name, info.iconID end
end

local function mountInfo(mountID)
	if C_MountJournal and C_MountJournal.GetMountInfoByID then
		local name, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
		return name, spellID, icon
	end
end

-- The mount journal entry a spell summons (e.g. a paladin's Summon Warhorse), or nil.
local function mountFromSpell(spellID)
	if C_MountJournal and C_MountJournal.GetMountFromSpell then
		return C_MountJournal.GetMountFromSpell(spellID)
	end
end

-- Summon the way the mount journal's own button does: by journal ID, or dismount if it's the
-- mount you're on. Casting the mount's spell by ID didn't work for class mounts.
local function summonMount(mountID)
	if not C_MountJournal then return end
	local active = select(4, C_MountJournal.GetMountInfoByID(mountID))
	if active and C_MountJournal.Dismiss then
		C_MountJournal.Dismiss()
	elseif C_MountJournal.SummonByID then
		C_MountJournal.SummonByID(mountID)
	end
end

-- Cooldowns: start, duration, modRate as the game returns them. In combat these may be secret
-- values, which can be handed to a Cooldown frame but not compared, so nothing here tests them.
local function itemCooldown(itemID)
	if C_Container and C_Container.GetItemCooldown then
		return C_Container.GetItemCooldown(itemID)
	elseif C_Item and C_Item.GetItemCooldown then
		return C_Item.GetItemCooldown(itemID)
	elseif GetItemCooldown then
		return GetItemCooldown(itemID)
	end
end

local function spellCooldown(spellID)
	local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
	if info then return info.startTime, info.duration, info.modRate end
end

local function petInfo(petGUID)
	if C_PetJournal and C_PetJournal.GetPetInfoByPetID then
		local _, customName, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(petGUID)
		return customName or name, icon
	end
end

local function equipmentSetInfo(name)
	local id = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID and C_EquipmentSet.GetEquipmentSetID(name)
	if id then
		local _, icon = C_EquipmentSet.GetEquipmentSetInfo(id)
		return icon
	end
end

-- label: shown in the editor and tags; valid(value): saved-data check;
-- icon/name(value): may return nil while the game is still loading data;
-- secure(value): actionType, attribute, attributeValue for SecureActionButtonTemplate, or
-- run(value): an insecure function for things with no secure action type.
-- binding(value): optional; picks one of those itself (returns like Actions.Binding).
-- cooldown(value): optional; start, duration, modRate.
local KINDS = {
	item = {
		label = "Item",
		valid = positiveInt,
		icon = itemIcon,
		name = itemName,
		count = itemCount,
		cooldown = itemCooldown,
		secure = function(id) return "item", "item", "item:" .. id end,
	},
	toy = {
		label = "Toy",
		valid = positiveInt,
		icon = itemIcon,
		name = itemName,
		cooldown = itemCooldown,
		secure = function(id) return "toy", "toy", id end,
	},
	spell = {
		label = "Spell",
		valid = positiveInt,
		icon = function(id) return select(2, spellInfo(id)) end,
		name = function(id) return (spellInfo(id)) end,
		cooldown = spellCooldown,
		binding = function(id)
			-- A mount's spell dragged from the spellbook summons like the mount itself.
			local mountID = mountFromSpell(id)
			if mountID then
				return nil, nil, nil, function() summonMount(mountID) end
			end
			return "spell", "spell", id
		end,
	},
	mount = {
		label = "Mount",
		valid = positiveInt,
		icon = function(id) return select(3, mountInfo(id)) end,
		name = function(id) return (mountInfo(id)) end,
		run = summonMount,
	},
	pet = {
		label = "Pet",
		valid = function(v) return shortString(v) and v:match("^BattlePet%-") ~= nil end,
		icon = function(guid) return select(2, petInfo(guid)) end,
		name = function(guid) return (petInfo(guid)) end,
		run = function(guid)
			if C_PetJournal and C_PetJournal.SummonPetByGUID then
				C_PetJournal.SummonPetByGUID(guid)
			end
		end,
	},
	equipset = {
		label = "Equipment set",
		valid = shortString,
		icon = equipmentSetInfo,
		name = function(name) return name end,
		secure = function(name) return "equipmentset", "equipmentset", name end,
	},
}

-- Attributes Apply() must clear from every slot before writing new ones.
Actions.ATTRIBUTES = { "macrotext", "item", "toy", "spell", "equipmentset" }

function Actions.IsAction(kind)
	return KINDS[kind] ~= nil
end

function Actions.Valid(kind, value)
	local k = KINDS[kind]
	return k ~= nil and k.valid(value) == true
end

function Actions.KindLabel(kind)
	return KINDS[kind] and KINDS[kind].label
end

function Actions.Icon(kind, value)
	local k = KINDS[kind]
	return k and k.icon(value)
end

function Actions.Name(kind, value)
	local k = KINDS[kind]
	return k and k.name(value)
end

-- Number to show on the slice (items only), or nil.
function Actions.Count(kind, value)
	local k = KINDS[kind]
	return k and k.count and k.count(value)
end

-- The name of the spell a mount casts ("Summon Warhorse" for the mount "Warhorse"), or nil.
function Actions.MountSpellName(mountID)
	local spellID = select(2, mountInfo(mountID))
	return spellID and (spellInfo(spellID))
end

-- start, duration, modRate of the action's cooldown (possibly secret values), or nil.
function Actions.Cooldown(kind, value)
	local k = KINDS[kind]
	if k and k.cooldown then return k.cooldown(value) end
end

-- actionType, attribute, attributeValue for the secure button; or nil plus an insecure runner.
function Actions.Binding(kind, value)
	local k = KINDS[kind]
	if not k then return nil end
	if k.binding then return k.binding(value) end
	if k.run then
		return nil, nil, nil, function() k.run(value) end
	end
	return k.secure(value)
end

local function trimMacro(body)
	return (body or ""):gsub("%s+$", ""):sub(1, ns.Slices.MACRO_MAX)
end

-- Turn whatever is on the cursor into a slice. Returns slice or nil, errorMessage
-- (nil, nil when the cursor is empty).
function Actions.FromCursor()
	if not GetCursorInfo then return nil end
	local what, a, _, c = GetCursorInfo()
	if not what then return nil end

	if what == "item" and positiveInt(a) then
		-- Learned toys aren't in your bags; the toy box hands them over as items.
		if PlayerHasToy and PlayerHasToy(a) and (itemCount(a) or 0) == 0 then
			return { kind = "toy", value = a }
		end
		return { kind = "item", value = a }
	elseif what == "spell" and positiveInt(c) then -- spellIndex, bookType, spellID
		return { kind = "spell", value = c }
	elseif what == "mount" and positiveInt(a) then -- mountID, mountIndex
		return { kind = "mount", value = a }
	elseif what == "battlepet" and KINDS.pet.valid(a) then
		return { kind = "pet", value = a }
	elseif what == "macro" and GetMacroInfo then
		local name, icon, body = GetMacroInfo(a)
		local text = trimMacro(body)
		if text ~= "" then
			return { kind = "macro", value = text, label = name and name:sub(1, ns.LABEL_MAX), icon = icon }
		end
	elseif what == "equipmentset" then
		local name = a
		if type(a) == "number" and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo then
			name = C_EquipmentSet.GetEquipmentSetInfo(a)
		end
		if shortString(name) then
			return { kind = "equipset", value = name }
		end
	end
	return nil, "Jest can't put that on the wheel."
end

-- Is the cursor holding something that could be dropped on the wheel?
function Actions.CursorHasAction()
	return GetCursorInfo ~= nil and (Actions.FromCursor()) ~= nil
end
