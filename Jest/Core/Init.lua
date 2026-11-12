-- Namespace, printing, and a tiny event dispatcher shared by every module.
-- Every file receives the same private table `ns` via `...`.
local addonName, ns = ...

ns.name = addonName
ns.debug = false -- session-only; toggled with /jest debug
ns.MAX_SLICES = 12

function ns.Print(...)
	print("|cff66ccffJest|r", ...)
end

function ns.Debug(...)
	if ns.debug then
		print("|cff888888Jest debug|r", ...)
	end
end

-- Keybinding labels shown in Options -> Keybindings -> AddOns -> Jest.
BINDING_HEADER_JEST = "Jest"
_G["BINDING_NAME_CLICK JestWheelButton:LeftButton"] = "Open emote wheel (hold)"
_G["BINDING_NAME_CLICK JestWheelButton:repeat"] = "Repeat last emote"

-- Event dispatcher: ns.On("EVENT", function(event, ...) end)
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(event, ...)
	end
end)

-- All files are loaded by the time ADDON_LOADED fires for us, and SavedVariables are available.
ns.On("ADDON_LOADED", function(_, name)
	if name ~= addonName then return end
	ns.DB.Init()
	ns.SecureWheel.Apply()
end)
