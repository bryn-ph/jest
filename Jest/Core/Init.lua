local addonName, ns = ...

ns.name = addonName
ns.debug = false
ns.MAX_SLICES = 12

function ns.Print(...)
	print("|cff66ccffJest|r", ...)
end

function ns.Debug(...)
	if ns.debug then
		print("|cff888888Jest debug|r", ...)
	end
end

-- Escape "|" so user text can't inject chat markup (links, textures, colours) when printed.
function ns.Escape(text)
	return (tostring(text):gsub("|", "||"))
end

BINDING_HEADER_JEST = "Jest"
_G["BINDING_NAME_CLICK JestWheelButton:LeftButton"] = "Open emote wheel (hold)"
_G["BINDING_NAME_CLICK JestWheelButton:repeat"] = "Repeat last emote"

-- Events ---------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

function ns.Off(event)
	handlers[event] = nil
	eventFrame:UnregisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for _, fn in ipairs(list) do
		fn(event, ...)
	end
end)

-- Config changes -------------------------------------------------------------
-- Editors (slash commands, options panel) write to the DB and then call ns.Changed(), which
-- re-applies the secure wheel (deferred while in combat) and refreshes any open UI.

local changeListeners = {}

function ns.OnChanged(fn)
	table.insert(changeListeners, fn)
end

function ns.Changed()
	ns.SecureWheel.Apply()
	for _, fn in ipairs(changeListeners) do
		fn()
	end
end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= addonName then return end
	ns.Off("ADDON_LOADED")
	ns.DB.Init()
	ns.Panel.Register()
	ns.SecureWheel.Apply()
end)

-- Referenced by the TOC's AddonCompartmentFunc.
function Jest_OnAddonCompartmentClick()
	ns.Panel.Open()
end
