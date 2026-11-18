local _, ns = ...

-- A slice is { kind = "emote" | "macro", value = string, icon = fileID | path | nil, label = string | nil }.
-- icon and label are only stored when the user overrides them (see Core/Slices.lua).
ns.Defaults = {
	profile = {
		radius = 110, -- centre to slice icons
		deadZone = 28, -- releasing inside this radius cancels
		scale = 1,
		sounds = true,
		rememberWheel = false, -- reopen on the wheel used last, instead of the first
		wheels = {
			{
				name = "Emotes",
				-- Clockwise from 12 o'clock.
				slices = {
					{ kind = "emote", value = "WAVE" },
					{ kind = "emote", value = "DANCE" },
					{ kind = "emote", value = "CHEER" },
					{ kind = "emote", value = "LAUGH" },
					{ kind = "emote", value = "BOW" },
					{ kind = "emote", value = "SALUTE" },
					{ kind = "emote", value = "APPLAUD" },
					{ kind = "emote", value = "THANK" },
				},
			},
		},
	},
}

-- Allowed range for each numeric profile setting: { min, max }.
-- Account-wide, not per profile: the minimap button is part of your UI, not your wheels.
-- angle: degrees anticlockwise from 3 o'clock (225 = bottom left).
ns.Defaults.minimap = { angle = 225, hide = false }

ns.Limits = {
	radius = { 40, 300 },
	deadZone = { 8, 100 },
	scale = { 0.5, 2 },
}

ns.LABEL_MAX = 40
ns.WHEEL_NAME_MAX = 24
ns.PROFILE_NAME_MAX = 32
ns.NEW_WHEEL_SLICES = 4 -- empty slices a new wheel starts with, ready to drop things onto

-- Emotes have no icons of their own; these are thematic stand-ins.
ns.EmoteIcons = {
	WAVE = "Interface\\Icons\\Ability_Warrior_RallyingCry",
	DANCE = "Interface\\Icons\\INV_Misc_Drum_01",
	CHEER = "Interface\\Icons\\Achievement_Reputation_08",
	LAUGH = "Interface\\Icons\\Spell_Shadow_Charm",
	BOW = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
	SALUTE = "Interface\\Icons\\Ability_Warrior_BattleShout",
	APPLAUD = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
	THANK = "Interface\\Icons\\Achievement_Reputation_01",
}

ns.KindIcons = {
	macro = "Interface\\Icons\\INV_Misc_Gear_01",
}

ns.FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark

-- Trim the bevel baked into the outer edge of standard icons so the art fills round masks.
function ns.CropIcon(texture)
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
