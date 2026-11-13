local _, ns = ...

-- A slice is { kind = "emote" | "macro", value = string, icon = fileID | path | nil, label = string | nil }.
-- icon and label are only stored when the user overrides them (see Core/Slices.lua).
ns.Defaults = {
	profile = {
		radius = 110, -- centre to slice icons
		deadZone = 28, -- releasing inside this radius cancels
		scale = 1,
		sounds = true,
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
ns.Limits = {
	radius = { 40, 300 },
	deadZone = { 8, 100 },
	scale = { 0.5, 2 },
}

ns.LABEL_MAX = 40

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
