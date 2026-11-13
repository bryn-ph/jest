-- Helpers that derive display data and validity from a slice definition.
local _, ns = ...

local Slices = {}
ns.Slices = Slices

Slices.MACRO_MAX = 255

-- Slice kinds: "emote" (a built-in emote token, performed natively) and "macro" (macro text run
-- by the secure button; custom emote lines are macros like "/e waves.").
function Slices.HasAction(s)
	return s and (s.kind == "emote" or s.kind == "macro")
		and type(s.value) == "string" and s.value ~= ""
end

-- Emote slices go through the chat/emote API (testable from the panel, affected by chat lockdown).
function Slices.IsChat(s)
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

-- Normalise and validate user input for a slice. Returns the value to store, or nil + error.
function Slices.Validate(kind, value)
	value = trim(value or "")
	if value == "" then
		return nil, "Enter something for this slice to do."
	end
	if kind == "emote" then
		local token = ns.Emotes.Resolve(value)
		if not token then
			return nil, ("Unknown emote '%s'. Try /jest emotes to list them."):format(value)
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

-- "134400" -> 134400, "Spell_Nature_Polymorph" -> "Interface\\Icons\\Spell_Nature_Polymorph", paths unchanged.
function Slices.ParseIcon(text)
	text = trim(text or "")
	if text == "" then return nil end
	if tonumber(text) then return tonumber(text) end
	if text:find("[\\/]") then return text end
	return "Interface\\Icons\\" .. text
end

-- Key shown on each slice while the wheel is open (1-9, then 0 for slice 10).
function Slices.KeyLabel(i)
	if i <= 9 then return tostring(i) end
	if i == 10 then return "0" end
	return ""
end
