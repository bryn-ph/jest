-- Small shared UI widgets for the options panel and icon picker.
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}
local BORDER = { 0.4, 0.4, 0.4, 1 }
local BORDER_FOCUS = { 1, 0.82, 0, 1 }

local function setBorder(box, c)
	box:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
end

-- Single-line text input.
-- Deliberately NOT built on InputBoxTemplate: on WoW: Forever, Backspace does nothing in boxes
-- created from that template (it pulls in NarrationEditBoxMixin; exact cause unconfirmed), while
-- plain EditBoxes behave normally.
-- Callers that need focus-lost behaviour should use HookScript("OnEditFocusLost", ...) so the
-- focus styling below is kept.
function Widgets.Input(parent, width, maxLetters)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width, 22)
	box:SetBackdrop(BACKDROP)
	box:SetBackdropColor(0, 0, 0, 0.5)
	setBorder(box, BORDER)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(6, 6, 0, 0)
	box:SetAutoFocus(false)
	if maxLetters then
		box:SetMaxLetters(maxLetters)
	end
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self)
		setBorder(self, BORDER_FOCUS)
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		setBorder(self, BORDER)
		self:HighlightText(0, 0)
	end)
	Widgets.TraceInput(box)
	return box
end

-- /jest debug: log every text change so input problems can be diagnosed from chat.
-- Callers must use HookScript (not SetScript) for OnTextChanged or this trace is lost.
function Widgets.TraceInput(box, name)
	if name then box.debugName = name end
	box:HookScript("OnTextChanged", function(self, userInput)
		if ns.debug then
			ns.Debug(("[input %s] changed userInput=%s text=%q"):format(
				self.debugName or "?", tostring(userInput), self:GetText()))
		end
	end)
end
