-- Helpers that derive display data and validity from a slice definition.
local _, ns = ...

local Slices = {}
ns.Slices = Slices

Slices.MACRO_MAX = 255

function Slices.HasAction(s)
	return s and (s.kind == "emote" or s.kind == "text" or s.kind == "macro")
		and type(s.value) == "string" and s.value ~= ""
end

function Slices.IsChat(s)
	return s and (s.kind == "emote" or s.kind == "text")
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
	if s.kind == "text" then
		local v = s.value or ""
		return #v > 18 and (v:sub(1, 17) .. "…") or v
	end
	if s.kind == "macro" then return "Macro" end
	return "Empty"
end

-- Key shown on each slice while the wheel is open (1-9, then 0 for slice 10).
function Slices.KeyLabel(i)
	if i <= 9 then return tostring(i) end
	if i == 10 then return "0" end
	return ""
end
