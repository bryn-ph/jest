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

-- Emotes matching `query` (token or slash command, case-insensitive, leading "/" ignored).
-- Prefix matches come first, then substring matches; at most `limit` results.
function Emotes.Search(query, limit)
	if not list then scan() end
	local q = (query or ""):gsub("^/", ""):lower()
	if q == "" then return {} end
	local prefix, contains = {}, {}
	for _, e in ipairs(list) do
		local token = e.token:lower()
		local cmd = e.cmd and e.cmd:gsub("^/", ""):lower() or token
		if token:sub(1, #q) == q or cmd:sub(1, #q) == q then
			prefix[#prefix + 1] = e
		elseif token:find(q, 1, true) or cmd:find(q, 1, true) then
			contains[#contains + 1] = e
		end
	end
	local results = {}
	for _, group in ipairs({ prefix, contains }) do
		for _, e in ipairs(group) do
			if #results >= limit then return results end
			results[#results + 1] = e
		end
	end
	return results
end

-- "WAVE" -> "Wave" (prefers the localized slash command when available).
function Emotes.Label(token)
	if not list then scan() end
	local entry = byToken[token]
	local base = (entry and entry.cmd and entry.cmd:gsub("^/", "")) or token or "?"
	return base:sub(1, 1):upper() .. base:sub(2):lower()
end
