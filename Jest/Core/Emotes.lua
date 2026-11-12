-- Discovers the client's emote list from the EMOTE<i>_TOKEN / EMOTE<i>_CMD<j> globals.
local _, ns = ...

local Emotes = {}
ns.Emotes = Emotes

local list     -- array of { token = "WAVE", cmd = "/wave" }
local byToken  -- "WAVE" -> entry
local byCmd    -- "wave" -> entry (lower-case, no slash)

local function scan()
	list, byToken, byCmd = {}, {}, {}
	for i = 1, 1500 do
		local token = _G["EMOTE" .. i .. "_TOKEN"]
		if token then
			local entry = { token = token, cmd = _G["EMOTE" .. i .. "_CMD1"] }
			table.insert(list, entry)
			byToken[token] = entry
			for j = 1, 4 do
				local cmd = _G["EMOTE" .. i .. "_CMD" .. j]
				if cmd then
					byCmd[cmd:gsub("^/", ""):lower()] = byCmd[cmd:gsub("^/", ""):lower()] or entry
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.token < b.token end)
end

function Emotes.All()
	if not list then scan() end
	return list
end

-- Accepts "WAVE", "wave" or "/wave" and returns the canonical token, or nil.
function Emotes.Resolve(input)
	if not list then scan() end
	if not input or input == "" then return nil end
	local bare = input:gsub("^/", "")
	local entry = byToken[bare:upper()] or byCmd[bare:lower()]
	return entry and entry.token or nil
end

-- "WAVE" -> "Wave" (prefers the localized slash command when available).
function Emotes.Label(token)
	if not list then scan() end
	local entry = byToken[token]
	local base = (entry and entry.cmd and entry.cmd:gsub("^/", "")) or token or "?"
	return base:sub(1, 1):upper() .. base:sub(2):lower()
end
