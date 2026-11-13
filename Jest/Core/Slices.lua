-- Display data and validation for slice definitions.
local _, ns = ...

local Slices = {}
ns.Slices = Slices

Slices.MACRO_MAX = 255
local ICON_PATH_MAX = 260

-- "emote": a built-in emote token, performed through the emote API.
-- "macro": macro text run by the secure button (a custom emote line is "/e ...").
function Slices.HasAction(s)
	return s and (s.kind == "emote" or s.kind == "macro")
		and type(s.value) == "string" and s.value ~= ""
end

function Slices.IsEmote(s)
	return s and s.kind == "emote"
end

function Slices.Icon(s)
	if not s then return ns.FALLBACK_ICON end
	if s.icon then return s.icon end
	if s.kind == "emote" then return ns.EmoteIcons[s.value] or ns.FALLBACK_ICON end
	return ns.KindIcons[s.kind] or ns.FALLBACK_ICON
end

function Slices.Label(s)
	if not s then return "" end
	if s.label then return s.label end
	if s.kind == "emote" then return ns.Emotes.Label(s.value) end
	if s.kind == "macro" then return "Macro" end
	return "Empty"
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns the value to store, or nil and an error message.
function Slices.Validate(kind, value)
	value = trim(value or "")
	if value == "" then
		return nil, "Enter something for this slice to do."
	end
	if kind == "emote" then
		local token = ns.Emotes.Resolve(value)
		if not token then
			return nil, ("Unknown emote '%s'. Try /jest emotes to list them."):format(ns.Escape(value))
		end
		return token
	elseif kind == "macro" then
		if #value > Slices.MACRO_MAX then
			return nil, ("Macro is %d characters; the limit is %d."):format(#value, Slices.MACRO_MAX)
		end
		return value
	end
	return nil, "Kind must be emote or macro."
end

-- "134400" -> 134400; "Spell_Nature_Polymorph" -> "Interface\\Icons\\Spell_Nature_Polymorph";
-- anything containing a slash is taken as a texture path. Returns nil for unusable input.
function Slices.ParseIcon(text)
	text = trim(text or "")
	if text == "" or #text > ICON_PATH_MAX then return nil end
	if text:match("^%d+$") then return tonumber(text) end
	if text:find("[\\/]") then return text end
	if not text:match("^[%w_%-]+$") then return nil end
	return "Interface\\Icons\\" .. text
end

-- Number key that fires slice i while the wheel is open (1-9, then 0 for the tenth).
function Slices.KeyLabel(i)
	if i <= 9 then return tostring(i) end
	if i == 10 then return "0" end
	return ""
end
