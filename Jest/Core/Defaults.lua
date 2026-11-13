local _, ns = ...

-- Slice shape: { kind = "emote"|"macro", value = string, icon = fileID|path|nil, label = string|nil }
-- (Schema v1 also had kind = "text"; DB.lua migrates those to "/e ..." macros.)
-- icon/label are only stored when the user overrides them; otherwise they are derived (Core/Slices.lua).
ns.Defaults = {
	profile = {
		radius = 110,   -- distance from centre to slice icons (wheel units)
		deadZone = 28,  -- release inside this radius cancels (wheel units)
		scale = 1,      -- overall wheel scale
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

-- Emotes have no native icons; these are hand-picked thematic stand-ins.
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

-- Standard icons have a dark bevelled border baked into the outer ~8%. Cropping it lets the
-- artwork fill round masks and square frames edge to edge.
function ns.CropIcon(texture)
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
