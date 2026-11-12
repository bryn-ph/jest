"""Load the addon in TOC order against a mocked WoW API and exercise the main paths."""
import pathlib, re, sys
from lupa import lua51

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1]) / "Jest"
lua = lua51.LuaRuntime(unpack_returned_tuples=True)

MOCK = r"""
local out = {}
_G.__out = out
print = function(...) local t = {} for i = 1, select('#', ...) do t[#t+1] = tostring((select(i, ...))) end out[#out+1] = table.concat(t, ' ') end

local function newObj(name)
  local o = { __attrs = {}, __scripts = {}, __shown = true, __name = name }
  local m = {}
  function m.SetAttribute(self, k, v) self.__attrs[k] = v end
  function m.GetAttribute(self, k) return self.__attrs[k] end
  function m.SetScript(self, k, f) self.__scripts[k] = f end
  function m.GetScript(self, k) return self.__scripts[k] end
  function m.Show(self) self.__shown = true end
  function m.Hide(self) self.__shown = false end
  function m.IsShown(self) return self.__shown end
  function m.GetEffectiveScale() return 1 end
  function m.GetName(self) return self.__name end
  function m.CreateTexture() return newObj() end
  function m.CreateMaskTexture() return newObj() end
  function m.CreateFontString() return newObj() end
  function m.CreateAnimationGroup(self) local g = newObj(); g.Play = function(gg) local f = gg.__scripts.OnFinished; if f then f(gg) end end; return g end
  function m.CreateAnimation() return newObj() end
  function m.RegisterEvent(self, e) end
  function m.HookScript(self, k, f) local prev = self.__scripts[k]; self.__scripts[k] = function(...) if prev then prev(...) end f(...) end end
  function m.EnableKeyboard(self, v) self.__kb = not not v end
  function m.SetText(self, t) self.__text = t end
  function m.GetText(self) return self.__text or '' end
  function m.SetShown(self, v) self.__shown = not not v end
  function m.SetEnabled(self, v) self.__enabled = not not v end
  function m.IsEnabled(self) return self.__enabled ~= false end
  function m.Click(self, b) local f = self.__scripts.OnClick; if f then f(self, b or 'LeftButton') end end
  -- Unknown Capitalised names act as no-op methods; lower-case fields stay nil like real frames.
  setmetatable(o, { __index = function(t, k) if m[k] then return m[k] end if type(k) == 'string' and k:match('^%u') then return function() end end end })
  return o
end
_G.newObj = newObj
UIParent = newObj("UIParent")
__templates = {}
CreateFrame = function(_, name, _, tmpl) if tmpl then __templates[tmpl] = (__templates[tmpl] or 0) + 1 end local f = newObj(name); if name then _G[name] = f end; return f end
InCombatLockdown = function() return false end
GetCursorPosition = function() return __cx or 500, __cy or 500 end
GetTime = function() return __t or 0 end
IsMouselooking = function() return false end
PlaySound = function() end
SOUNDKIT = { U_CHAT_SCROLL_BUTTON = 1, IG_MAINMENU_OPTION_CHECKBOX_ON = 2, IG_MAINMENU_OPTION_CHECKBOX_OFF = 3 }
ClearOverrideBindings = function() end
SecureHandlerSetFrameRef = function() end
SecureHandlerWrapScript = function() end
SlashCmdList = {}
__sent = {}
C_ChatInfo = {
  PerformEmote = function(t) __sent[#__sent+1] = 'emote:' .. t end,
  SendChatMessage = function(m, c) __sent[#__sent+1] = c .. ':' .. m end,
  InChatMessagingLockdown = function() return false end,
}
-- Settings / bindings / UI globals used by the options panel
__settings = {}
Settings = {
  VarType = { Number = 'number', Boolean = 'boolean' },
  RegisterCanvasLayoutCategory = function(frame, name) __canvas = frame; return { GetID = function() return 42 end } end,
  RegisterVerticalLayoutSubcategory = function(parent, name) return { name = name } end,
  RegisterAddOnCategory = function() end,
  RegisterProxySetting = function(cat, var, t, name, def, get, set) local s = { var = var, get = get, set = set }; __settings[var] = s; return s end,
  CreateSliderOptions = function() return newObj() end,
  CreateSlider = function() end,
  CreateCheckbox = function() end,
  OpenToCategory = function(id) __opened = id end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
__binds = {}
GetBindingKey = function(cmd) for k, v in pairs(__binds) do if v == cmd then return k end end end
GetBindingAction = function(k) return __binds[k] or '' end
SetBinding = function(k, cmd) __binds[k] = cmd; return true end
SaveBindings = function() end
GetCurrentBindingSet = function() return 1 end
GetBindingText = function(k) return k end
IsAltKeyDown = function() return false end
IsControlKeyDown = function() return __ctrl or false end
IsShiftKeyDown = function() return false end
GameTooltip = newObj('GameTooltip')
UISpecialFrames = {}
ChatFontNormal = {}
local toks = { 'WAVE', 'DANCE', 'CHEER', 'LAUGH', 'BOW', 'SALUTE', 'APPLAUD', 'THANK', 'ROAR' }
for i, t in ipairs(toks) do _G['EMOTE' .. i .. '_TOKEN'] = t; _G['EMOTE' .. i .. '_CMD1'] = '/' .. t:lower() end
"""
lua.execute(MOCK)

ns = lua.table()
toc = (root / "Jest.toc").read_text(encoding="utf-8")
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
loader = lua.eval("function(src, name, ns) local f = assert(loadstring(src, name)); f('Jest', ns) end")
for f in files:
    loader((root / f.replace("\\", "/")).read_text(encoding="utf-8"), "@" + f, ns)

run = lua.eval("function(...) " + r"""
local ns = ...
local fails = {}
local function check(cond, msg) if not cond then fails[#fails+1] = msg end end

-- ADDON_LOADED
for _, fn in ipairs({ ns.DB.Init, ns.Panel.Register, ns.SecureWheel.Apply }) do fn() end
local btn = JestWheelButton
check(btn.__attrs.count == 8, 'count attr = 8')
check(btn.__attrs['type-slice1'] == 'jest', 'slice1 uses custom type')
check(btn.__attrs.useOnKeyDown == false, 'useOnKeyDown false')

-- custom type fires native emote
btn:jest(nil, 'slice2')
check(__sent[#__sent] == 'emote:DANCE', 'slice2 performs DANCE, got ' .. tostring(__sent[#__sent]))

-- slash commands
local slash = SlashCmdList.JEST
slash('set 3 macro /cast Foo\\n/say hi')
check(btn.__attrs['type-slice3'] == 'macro', 'slice3 macro type')
check(btn.__attrs['macrotext-slice3'] == '/cast Foo\n/say hi', 'macro newline escape')
slash('set 9 text waves a tiny flag.')
check(btn.__attrs.count == 9, 'append to 9')
btn:jest(nil, 'slice9')
check(__sent[#__sent] == 'EMOTE:waves a tiny flag.', 'text slice sends EMOTE')
slash('set 1 emote /roar')
check(ns.DB.Wheel().slices[1].value == 'ROAR', '/roar resolves to ROAR')
slash('set 1 emote nonsense')
check(ns.DB.Wheel().slices[1].value == 'ROAR', 'invalid emote rejected')
slash('move 9 1'); check(ns.DB.Wheel().slices[1].kind == 'text', 'move works')
slash('remove 1'); check(#ns.DB.Wheel().slices == 8, 'remove works')
slash('icon 2 Spell_Nature_Polymorph'); check(ns.DB.Wheel().slices[2].icon == 'Interface\\Icons\\Spell_Nature_Polymorph', 'icon name expands')
slash('label 2 Boop'); check(ns.Slices.Label(ns.DB.Wheel().slices[2]) == 'Boop', 'label override')
slash('radius 150'); check(ns.DB.Profile().radius == 150, 'radius')
slash('deadzone 30'); check(btn.__attrs.deadzone == 30, 'deadzone attr')
slash('scale 1.5'); check(btn.__attrs.deadzone == 45, 'deadzone scaled')
slash('list'); slash('emotes A'); slash('help'); slash('debug'); slash('test 2'); slash('reset'); slash('sound off')

-- skin: open at (500,500), move up 100px, update, close as secure would
__cx, __cy = 500, 500
btn:JestOnOpen()
local skin = JestSkin
check(skin.__shown, 'skin shown on open')
__cx, __cy = 500, 650
skin.__scripts.OnUpdate(skin, 0.016)
__t = 0.1
skin.__scripts.OnUpdate(skin, 0.016)
btn:JestOnClose(1, 'mouse')
check(not skin.__shown, 'skin hidden after close anim')
btn:JestOnOpen(); btn:JestOnClose(nil, 'deadzone'); btn:JestOnOpen(); btn:JestOnClose(3, 'key'); btn:JestOnRepeat(3)

-- watchdog
btn:JestOnOpen(); __t = 100; skin.__scripts.OnUpdate(skin, 0.016)
check(not skin.__shown, 'watchdog closes')

-- combat queueing
InCombatLockdown = function() return true end
slash('reset yes')
check(btn.__attrs.deadzone == 45, 'no apply in combat')
InCombatLockdown = function() return false end
check(#ns.DB.Wheel().slices == 8, 'reset restored 8 slices')

-- ===== Options panel =====
SlashCmdList.JEST('')
check(__opened == 42, '/jest opens settings category')
__canvas:Show(); __canvas.__scripts.OnShow(__canvas)
local ui = ns.Panel._ui
check(ui.editorTitle:GetText() == 'Slice 1', 'editor shows slice 1')
check(ui.single:GetText() == 'WAVE', 'editor loads WAVE')

-- edit emote value and save via Enter
ui.single:SetText('/roar'); ui.single.__scripts.OnTextChanged(ui.single, true)
ui.single.__scripts.OnEnterPressed(ui.single)
check(ns.DB.Wheel().slices[1].value == 'ROAR', 'panel save resolves /roar')
check(ui.status:GetText() == 'Saved.', 'saved status, got ' .. ui.status:GetText())

-- invalid emote rejected, discarded on select
ui.single:SetText('nope'); ui.single.__scripts.OnTextChanged(ui.single, true)
ui.save:Click()
check(ns.DB.Wheel().slices[1].value == 'ROAR', 'invalid not saved')
ns.Panel.Select(2)
check(ui.editorTitle:GetText() == 'Slice 2', 'selected slice 2')
check(ui.single:GetText() == 'DANCE', 'slice 2 loaded')

-- switch kind emote -> macro converts, save
ui.kind.macro:Click()
check(ui.multiBox:GetText() == '/dance', 'emote->macro converts to /dance, got ' .. ui.multiBox:GetText())
ui.save:Click()
check(btn.__attrs['type-slice2'] == 'macro' and btn.__attrs['macrotext-slice2'] == '/dance', 'macro applied to secure button')
-- macro -> text
ui.kind.text:Click()
check(ui.single:GetText() == '', 'macro->text without /e clears')
ui.single:SetText('juggles.'); ui.single.__scripts.OnTextChanged(ui.single, true); ui.save:Click()
check(ns.DB.Wheel().slices[2].kind == 'text', 'now text')
ui.test:Click()
check(__sent[#__sent] == 'EMOTE:juggles.', 'test button sends text')

-- label commit
ui.labelBox:SetText('  Juggle '); ui.labelBox.__scripts.OnEditFocusLost(ui.labelBox)
check(ns.DB.Wheel().slices[2].label == 'Juggle', 'label trimmed + saved')

-- icon picker
ui.iconButton:Click()
local picker = JestIconPicker
check(picker and picker.__shown, 'picker opens')
-- click second grid icon (first child button created after close button)
ns.IconPicker.Close()
check(not picker.__shown, 'picker closes')
ui.iconButton:Click()
-- simulate manual entry path via ParseIcon + callback using Use button: find by scanning not possible; call Open with callback directly
ns.IconPicker.Open(nil, nil, function(icon) ns.DB.Wheel().slices[2].icon = icon end)
check(picker.__shown, 'picker reopen')

-- add / move / remove
ui.add:Click()
check(#ns.DB.Wheel().slices == 9, 'add slice')
check(ui.editorTitle:GetText() == 'Slice 9', 'selects new slice')
ui.up:Click()
check(ui.editorTitle:GetText() == 'Slice 8', 'move up follows selection')
ui.remove:Click()
check(#ns.DB.Wheel().slices == 8, 'remove slice')

-- keybind capture
-- regression: an idle capture button must not be keyboard-enabled (it swallowed Backspace)
check(not ui.bindWheel.__scripts.OnKeyDown and not ui.bindWheel.__kb, 'idle bind button has no key handler')
check(not ui.bindRepeat.__scripts.OnKeyDown and not ui.bindRepeat.__kb, 'idle repeat button has no key handler')
ui.bindWheel:Click('LeftButton')
check(ui.bindWheel.capturing, 'capturing')
__ctrl = true
ui.bindWheel.__scripts.OnKeyDown(ui.bindWheel, 'LCTRL')
check(ui.bindWheel.capturing, 'modifier alone ignored')
ui.bindWheel.__scripts.OnKeyDown(ui.bindWheel, 'Q')
__ctrl = false
check(__binds['CTRL-Q'] == 'CLICK JestWheelButton:LeftButton', 'CTRL-Q bound')
ui.bindWheel:Click('LeftButton'); ui.bindWheel:Click('Button4')
check(__binds['BUTTON4'] == 'CLICK JestWheelButton:LeftButton' and __binds['CTRL-Q'] == nil, 'rebinding to BUTTON4 clears old key')
ui.bindWheel:Click('RightButton')
check(GetBindingKey('CLICK JestWheelButton:LeftButton') == nil, 'right-click clears')
check(not ui.bindWheel.__scripts.OnKeyDown and not ui.bindWheel.__kb, 'key handler removed after capture')

-- appearance proxy settings
__settings.JEST_RADIUS.set(150.4)
check(ns.DB.Profile().radius == 150, 'radius proxy rounds')
__settings.JEST_SCALE.set(1.23)
check(math.abs(ns.DB.Profile().scale - 1.25) < 1e-9, 'scale rounds to .05')
check(btn.__attrs.deadzone == ns.DB.Profile().deadZone * 1.25, 'deadzone attr follows scale')
__settings.JEST_SOUNDS.set(false)
check(ns.DB.Profile().sounds == false, 'sounds proxy')

-- combat: save queues
InCombatLockdown = function() return true end
ns.Panel.Select(3)
ui.single:SetText('bow'); ui.single.__scripts.OnTextChanged(ui.single, true); ui.save:Click()
check(ui.status:GetText() == 'Saved. Applies when combat ends.', 'combat save message')
InCombatLockdown = function() return false end

-- regression: InputBoxTemplate swallows Backspace on Forever; it must not be used
check(not __templates.InputBoxTemplate, 'no InputBoxTemplate edit boxes')
check(ui.labelBox.__scripts.OnEditFocusLost ~= nil, 'label box keeps focus-lost handler')

-- regression: flicking Emote -> Text -> Macro -> Emote must not lose the saved action
ns.Panel.Select(5)
check(ui.single:GetText() == 'BOW', 'slice 5 is BOW')
ui.kind.text:Click()
check(ui.single:GetText() == '', 'text has no conversion from an emote')
check(ui.hint:GetText():find('Saved as Emote: Bow', 1, true), 'hint says what is saved')
check(ui.save:IsEnabled(), 'kind change counts as unsaved')
ui.kind.macro:Click()
check(ui.multiBox:GetText() == '/bow', 'macro seeded from the saved emote, got ' .. ui.multiBox:GetText())
ui.kind.emote:Click()
check(ui.single:GetText() == 'BOW', 'back to emote restores BOW, got ' .. ui.single:GetText())
check(not ui.save:IsEnabled(), 'back to the saved kind+value is not unsaved')
check(not ui.editorTitle:GetText():find('unsaved', 1, true), 'title not marked unsaved')
-- typed text survives a round trip too
ui.kind.text:Click(); ui.single:SetText('bows deeply.'); ui.single.__scripts.OnTextChanged(ui.single, true)
ui.kind.emote:Click(); ui.kind.text:Click()
check(ui.single:GetText() == 'bows deeply.', 'typed text kept across kind switches')
ui.revert:Click()
check(ui.single:GetText() == 'BOW' and not ui.save:IsEnabled(), 'revert restores saved')

-- hide settles drafts
ui.single:SetText('cheer'); ui.single.__scripts.OnTextChanged(ui.single, true)
__canvas.__scripts.OnHide(__canvas)
check(ns.DB.Wheel().slices[5].value == 'CHEER', 'hide auto-saves valid draft')

return fails
""" + " end")
fails = run(ns)
out = lua.globals().__out
for i in range(1, len(out) + 1):
    print("  chat>", out[i])
fl = [fails[i] for i in range(1, len(fails) + 1)]
print("FAILURES:" if fl else "Smoke test passed", *fl, sep="\n  ")
sys.exit(1 if fl else 0)
