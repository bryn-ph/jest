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
  function m.SetRotation(self, r) self.__rot = r end
  function m.SetAlpha(self, a) self.__alpha = a end
  function m.SetTexture(self, t) self.__tex = t end
  function m.SetFocus(self) self.__focus = true end
  function m.ClearFocus(self) self.__focus = false end
  function m.HasFocus(self) return self.__focus == true end
  function m.SetTexCoord(self, ...) __texcoords = __texcoords or {}; __texcoords[self] = { ... } end
  function m.GetCenter(self) return self.__cx or 300, self.__cy or 300 end
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
slash('set 9 macro /e waves a tiny flag.')
check(btn.__attrs.count == 9, 'append to 9')
check(btn.__attrs['type-slice9'] == 'macro' and btn.__attrs['macrotext-slice9'] == '/e waves a tiny flag.', 'custom emote line is a macro')
slash('set 4 text waves')
check(ns.DB.Wheel().slices[4].kind == 'emote', 'text kind no longer accepted')
slash('set 1 emote /roar')
check(ns.DB.Wheel().slices[1].value == 'ROAR', '/roar resolves to ROAR')
slash('set 1 emote nonsense')
check(ns.DB.Wheel().slices[1].value == 'ROAR', 'invalid emote rejected')
slash('move 9 1'); check(ns.DB.Wheel().slices[1].value == '/e waves a tiny flag.', 'move works')
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

-- ===== wedge art + eased highlight =====
local art = ns.Skin._art
local function near(a, b) return math.abs(a - b) < 1e-6 end
check(art.wedges[1] and art.wedges[1].__tex == [[Interface\AddOns\Jest\Media\wedge_8]], 'wedge texture path for 8 slices, got ' .. tostring(art.wedges[1] and art.wedges[1].__tex))
check(near(art.wedges[3].__rot, -math.rad(90)), 'wedge 3 rotated 90 deg clockwise')
check(art.glow.__tex == [[Interface\AddOns\Jest\Media\wedge_8_glow]], 'glow texture path')
check(ns.Geometry.AngleDelta(350, 10) == 20 and ns.Geometry.AngleDelta(10, 350) == -20, 'AngleDelta wraps')
__t = 200; __cx, __cy = 500, 500
btn:JestOnOpen()
check(art.highlight.__alpha == 0, 'highlight hidden on open')
__cx, __cy = 600, 500 -- right = slice 3 of 8
skin.__scripts.OnUpdate(skin, 0.016)
check(near(art.highlight.__rot, -math.rad(90)), 'highlight snaps to first hovered slice')
for _ = 1, 30 do skin.__scripts.OnUpdate(skin, 0.016) end
check(art.highlight.__alpha > 0.95, 'highlight fades in, alpha=' .. tostring(art.highlight.__alpha))
__cx, __cy = 500, 400 -- down = slice 5 (180 deg)
skin.__scripts.OnUpdate(skin, 0.016)
local mid = -art.highlight.__rot
check(mid > math.rad(90) and mid < math.rad(180), 'highlight sweeps, not snaps, between slices')
for _ = 1, 60 do skin.__scripts.OnUpdate(skin, 0.016) end
check(math.abs(-art.highlight.__rot - math.rad(180)) < math.rad(0.5), 'highlight settles on slice 5')
__cx, __cy = 500, 500 -- back to centre: fades out
for _ = 1, 30 do skin.__scripts.OnUpdate(skin, 0.016) end
check(art.highlight.__alpha < 0.05, 'highlight fades out in dead zone')
btn:JestOnClose(2, 'key')
check(near(art.highlight.__rot, -math.rad(45)) and art.highlight.__alpha == 1, 'fired slice highlighted at full alpha')
-- fallback: 1 slice has no wedge art
for _ = 1, 7 do SlashCmdList.JEST('remove 1') end
check(#ns.DB.Wheel().slices == 1, 'down to one slice')
check(not art.wedges[1].__shown and not art.highlight.__shown, 'no wedge art for a 1-slice wheel')
SlashCmdList.JEST('reset yes')
check(art.wedges[8].__shown and art.highlight.__shown, 'art back after reset')
-- restore the settings the later combat-queue test expects
SlashCmdList.JEST('radius 150'); SlashCmdList.JEST('deadzone 30'); SlashCmdList.JEST('scale 1.5')

-- watchdog
__t = 0
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
check(ui.emoteDropdown.__shown and not ui.multi.__shown, 'emote slices use the dropdown')
check(ui.kind.text == nil and ui.kind.emote and ui.kind.macro, 'only Emote and Macro types')
check(ui.emoteDropdown.value == 'WAVE' and ui.emoteDropdown.text:GetText() == 'Wave', 'dropdown shows Wave')
check(ui.emoteDropdown.cmd:GetText() == '/wave', 'dropdown shows the command')

-- pick an emote from the dropdown list: search + Enter picks and saves
local menu
local function pickFromMenu(query)
	ui.emoteDropdown:Click()
	menu = ns.EmoteMenu._ui()
	menu.search:SetText(query); menu.search.__scripts.OnTextChanged(menu.search, true)
	menu.search.__scripts.OnEnterPressed(menu.search)
end
pickFromMenu('roar')
check(ns.DB.Wheel().slices[1].value == 'ROAR', 'dropdown pick saves ROAR')
check(ui.status:GetText() == 'Saved.', 'saved status, got ' .. ui.status:GetText())
check(not menu.frame.__shown, 'list closes after pick')

-- invalid draft (empty macro) rejected, discarded on select
ui.kind.macro:Click()
ui.multiBox:SetText(''); ui.multiBox.__scripts.OnTextChanged(ui.multiBox, true)
ui.save:Click()
check(ns.DB.Wheel().slices[1].kind == 'emote' and ns.DB.Wheel().slices[1].value == 'ROAR', 'empty macro not saved')
ns.Panel.Select(2)
check(ui.editorTitle:GetText() == 'Slice 2', 'selected slice 2')
check(ui.status:GetText():find('discarded', 1, true), 'invalid draft discarded on select')
check(ui.emoteDropdown.value == 'DANCE', 'slice 2 loaded')

-- switch kind emote -> macro converts, save
ui.kind.macro:Click()
check(ui.multiBox:GetText() == '/dance', 'emote->macro converts to /dance, got ' .. ui.multiBox:GetText())
ui.save:Click()
check(btn.__attrs['type-slice2'] == 'macro' and btn.__attrs['macrotext-slice2'] == '/dance', 'macro applied to secure button')
check(not ui.test:IsEnabled(), 'test disabled for macro slices')
-- macro -> emote: a lone "/dance" converts back to the DANCE emote
ui.kind.emote:Click()
check(ui.emoteDropdown.value == 'DANCE', 'macro /dance converts to DANCE')
ui.save:Click()
check(ns.DB.Wheel().slices[2].kind == 'emote', 'saved as emote again')
ui.test:Click()
check(__sent[#__sent] == 'emote:DANCE', 'test button performs the emote')

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
check(ns.EmoteMenu.IsOpen(), 'new slice opens the emote list')
check(ui.emoteDropdown.text:GetText() == 'Choose an emote...', 'empty emote prompts a choice')
ns.EmoteMenu.Close()
-- preview wheel reflects the slices
local pv = ui.preview
check(pv.n == 9, 'preview shows 9 slices')
check(pv.slots[1].iconTexture == ns.Slices.Icon(ns.DB.Wheel().slices[1]), 'preview slot icon matches slice')
check(pv.highlighted == 9 and pv.emphasis == 9, 'preview highlights the selected slice')
check(pv.centreLabel:GetText() == 'Empty', 'preview centre shows selected (empty) slice')
-- drag slice 9 onto slice 8 (8 of 9 sits at 280 deg: left and slightly up of centre)
pv.frame.__cx, pv.frame.__cy = 300, 300
local slice8 = ns.DB.Wheel().slices[8]
__t = 50
pv.slots[9].__scripts.OnDragStart(pv.slots[9])
check(ui.ghost.__shown, 'drag ghost shown')
check(pv.slots[9].__alpha == 0.35, 'dragged slot dimmed')
__cx, __cy = 300 - 87, 300 + 15
pv.frame.__scripts.OnUpdate(pv.frame, 0.016)
check(pv.highlighted == 8, 'drop target highlighted, got ' .. tostring(pv.highlighted))
check(pv.centreLabel:GetText() == 'Swap here', 'centre explains the drop')
pv.slots[9].__scripts.OnDragStop(pv.slots[9])
check(not ui.ghost.__shown, 'ghost hidden after drop')
check(ns.DB.Wheel().slices[9] == slice8 and ns.DB.Wheel().slices[8].value == '', 'slices 8 and 9 swapped')
check(ui.editorTitle:GetText() == 'Slice 8', 'selection follows the dragged slice')
check(ui.status:GetText() == 'Swapped slices 9 and 8.', 'swap status, got ' .. ui.status:GetText())
-- the click that can follow a drag is ignored
pv.slots[3].__scripts.OnClick(pv.slots[3])
check(ui.editorTitle:GetText() == 'Slice 8', 'click right after drag ignored')
__t = 51
-- dropping in the centre cancels
local before = ns.DB.Wheel().slices[2]
pv.slots[2].__scripts.OnDragStart(pv.slots[2])
__cx, __cy = 300, 300
pv.frame.__scripts.OnUpdate(pv.frame, 0.016)
check(pv.centreLabel:GetText() == 'Cancel', 'centre says cancel over the dead zone')
pv.slots[2].__scripts.OnDragStop(pv.slots[2])
check(ns.DB.Wheel().slices[2] == before, 'drop in centre changes nothing')
check(pv.highlighted == 8, 'highlight returns to the selection')
-- clicking a slice selects it
__t = 52
pv.slots[3].__scripts.OnClick(pv.slots[3])
check(ui.editorTitle:GetText() == 'Slice 3', 'click selects slice')
ns.Panel.Select(8)
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
ui.kind.emote:Click()
pickFromMenu('bow')
check(ns.DB.Wheel().slices[3].value == 'BOW', 'combat pick saved to DB')
check(ui.status:GetText() == 'Saved. Applies when combat ends.', 'combat save message')
InCombatLockdown = function() return false end

-- regression: InputBoxTemplate swallows Backspace on Forever; it must not be used
check(not __templates.InputBoxTemplate, 'no InputBoxTemplate edit boxes')
check(ui.labelBox.__scripts.OnEditFocusLost ~= nil, 'label box keeps focus-lost handler')

-- regression: flicking Emote -> Macro -> Emote must not lose the saved action
ns.Panel.Select(5)
check(ui.emoteDropdown.value == 'BOW', 'slice 5 is BOW')
ui.kind.macro:Click()
check(ui.multiBox:GetText() == '/bow', 'macro seeded from the saved emote, got ' .. ui.multiBox:GetText())
check(ui.hint:GetText():find('Saved as Emote: Bow', 1, true), 'hint says what is saved')
check(ui.save:IsEnabled(), 'kind change counts as unsaved')
ui.kind.emote:Click()
check(ui.emoteDropdown.value == 'BOW', 'back to emote restores BOW, got ' .. tostring(ui.emoteDropdown.value))
check(not ui.save:IsEnabled(), 'back to the saved kind+value is not unsaved')
check(not ui.editorTitle:GetText():find('unsaved', 1, true), 'title not marked unsaved')
-- typed macro text survives a round trip too
ui.kind.macro:Click(); ui.multiBox:SetText('/bow\n/e bows deeply.'); ui.multiBox.__scripts.OnTextChanged(ui.multiBox, true)
ui.kind.emote:Click(); ui.kind.macro:Click()
check(ui.multiBox:GetText() == '/bow\n/e bows deeply.', 'typed macro kept across kind switches')
ui.revert:Click()
check(ui.emoteDropdown.value == 'BOW' and not ui.save:IsEnabled(), 'revert restores saved')

-- ===== UX pass =====
-- Emote search: prefix matches first, then substring
local found = ns.Emotes.Search('a', 10)
check(found[1].token == 'APPLAUD', 'search: prefix match first, got ' .. tostring(found[1] and found[1].token))
local anyContains = false
for _, e in ipairs(found) do if e.token == 'WAVE' then anyContains = true end end
check(anyContains, 'search: substring matches included')
check(#ns.Emotes.Search('', 10) == 0, 'search: empty query returns nothing')

-- Emote dropdown list
ns.Panel.Select(6)
ui.kind.emote:Click()
ui.emoteDropdown:Click()
menu = ns.EmoteMenu._ui()
check(menu.frame.__shown, 'emote list opens')
check(menu.search.__focus, 'search box focused on open')
local listed, currentRow = 0, nil
for _, r in ipairs(menu.rows) do
	if r.__shown then listed = listed + 1 end
	if r.__shown and r.current.__shown then currentRow = r.token end
end
check(listed == 9, 'every emote listed (mock has 9), got ' .. listed)
check(currentRow == ns.DB.Wheel().slices[6].value, 'current emote marked in the list')
menu.search:SetText('ro'); menu.search.__scripts.OnTextChanged(menu.search, true)
check(menu.rows[1].token == 'ROAR' and menu.rows[1].__shown, 'search filters, ROAR first')
menu.search.__scripts.OnArrowPressed(menu.search, 'DOWN')
menu.search.__scripts.OnArrowPressed(menu.search, 'UP')
menu.search.__scripts.OnEnterPressed(menu.search)
check(ns.DB.Wheel().slices[6].value == 'ROAR', 'Enter picks the highlighted emote and saves')
check(not menu.frame.__shown, 'list closes after pick')
ui.emoteDropdown:Click(); menu.rows[2]:Click() -- sorted: APPLAUD, BOW, ...
check(ns.DB.Wheel().slices[6].value == 'BOW', 'clicking a row picks it')
ui.emoteDropdown:Click(); check(menu.frame.__shown, 'dropdown click opens')
ui.emoteDropdown:Click(); check(not menu.frame.__shown, 'second click closes')
ui.emoteDropdown:Click()
menu.search:SetText('zzz'); menu.search.__scripts.OnTextChanged(menu.search, true)
check(not menu.rows[1].__shown, 'no rows when nothing matches')
menu.search.__scripts.OnEnterPressed(menu.search)
check(ns.DB.Wheel().slices[6].value == 'BOW', 'Enter with no match picks nothing')
menu.search.__scripts.OnEscapePressed(menu.search)
check(not menu.frame.__shown, 'Esc closes the list')
ui.emoteDropdown:Click(); ui.kind.macro:Click()
check(not menu.frame.__shown, 'switching to Macro closes the list')
ui.revert:Click()

-- Anim / Voice indicators (generated Core/EmoteData.lua)
local function feat(t) local k, a, v = ns.Emotes.Features(t); return tostring(k) .. tostring(a) .. tostring(v) end
check(feat('CHEER') == 'truetruetrue', 'CHEER animates and speaks')
check(feat('WAVE') == 'truetruefalse', 'WAVE animates only')
check(feat('BORED') == 'truefalsetrue', 'BORED speaks only')
check(feat('AGREE') == 'truefalsefalse', 'AGREE is text only')
check(feat('SIT') == 'truetruefalse', 'state emotes (sit) count as animation')
check(feat('NOT_AN_EMOTE') == 'falsefalsefalse', 'unknown emotes report unknown')
local b = ns.Widgets.EmoteBadges(UIParent)
b:SetEmote('CHEER'); check(b.anim.__shown and b.voice.__shown and not b.none.__shown, 'badges: both')
b:SetEmote('WAVE'); check(b.anim.__shown and not b.voice.__shown and not b.none.__shown, 'badges: anim only')
b:SetEmote('BORED'); check(not b.anim.__shown and b.voice.__shown and not b.none.__shown, 'badges: voice only')
b:SetEmote('AGREE'); check(not b.anim.__shown and not b.voice.__shown and b.none.__shown, 'badges: text only')
b:SetEmote('NOT_AN_EMOTE'); check(not b.anim.__shown and not b.voice.__shown and not b.none.__shown, 'badges: nothing for unknown')
ui.emoteDropdown:Click()
menu = ns.EmoteMenu._ui()
local rowsByToken = {}
for _, r in ipairs(menu.rows) do if r.__shown then rowsByToken[r.token] = r end end
check(rowsByToken.CHEER.badges.voice.__shown and rowsByToken.CHEER.badges.anim.__shown, 'list row shows CHEER as Anim + Voice')
check(rowsByToken.WAVE.badges.anim.__shown and not rowsByToken.WAVE.badges.voice.__shown, 'list row shows WAVE as Anim only')
ns.EmoteMenu.Close()
check(ui.emoteDropdown.badges.__shown and ui.emoteDropdown.badges.anim.__shown, 'dropdown button tags the chosen emote')
check(ns.Widgets.EmoteBadgeLegend():find('Anim', 1, true) and ns.Widgets.EmoteBadgeLegend():find('Voice', 1, true), 'legend explains both tags')

-- Anim / Voice filter chips (mock emotes: CHEER LAUGH APPLAUD THANK ROAR speak; all 9 animate)
local function visibleTokens()
	local t = {}
	for _, r in ipairs(menu.rows) do if r.__shown then t[#t + 1] = r.token end end
	return table.concat(t, ',')
end
ui.emoteDropdown:Click()
menu = ns.EmoteMenu._ui()
check(not menu.chips.anim.checked and not menu.chips.voice.checked, 'chips start off')
check(menu.count:GetText() == '9 emotes', 'no filter: full count, got ' .. menu.count:GetText())
menu.chips.voice:Click()
check(visibleTokens() == 'APPLAUD,CHEER,LAUGH,ROAR,THANK', 'Voice shows only speaking emotes, got ' .. visibleTokens())
check(menu.count:GetText() == '5 of 9 emotes', 'filtered count, got ' .. menu.count:GetText())
check(menu.search.__focus, 'search keeps focus after clicking a chip')
menu.chips.anim:Click()
check(visibleTokens() == 'APPLAUD,CHEER,LAUGH,ROAR,THANK', 'Anim + Voice requires both')
menu.chips.voice:Click()
check(menu.count:GetText() == '9 emotes', 'Anim alone keeps all animated emotes')
menu.chips.voice:Click()
menu.search:SetText('ro'); menu.search.__scripts.OnTextChanged(menu.search, true)
check(visibleTokens() == 'ROAR', 'chips combine with search, got ' .. visibleTokens())
ns.EmoteMenu.Close()
ui.emoteDropdown:Click()
check(menu.chips.voice.checked and visibleTokens() == 'APPLAUD,CHEER,LAUGH,ROAR,THANK', 'chips persist between openings')
menu.chips.anim:Click(); menu.chips.voice:Click()
check(visibleTokens():find('WAVE', 1, true), 'chips off shows everything again')
ns.EmoteMenu.Close()

-- Segmented control reflects the draft kind; unsaved tag follows dirty state
check(ui.kindSwitch.buttons.emote.bg.__shown and not ui.kindSwitch.buttons.macro.bg.__shown, 'segmented shows emote selected')
ui.kind.macro:Click()
check(ui.kindSwitch.buttons.macro.bg.__shown, 'segmented follows switch')
check(ui.unsaved.__shown, 'unsaved tag shown when dirty')
ui.revert:Click()
check(not ui.unsaved.__shown, 'unsaved tag hidden after revert')

-- Label placeholder shows the default label; list shows kind tags
check(ui.labelBox.placeholder and ui.labelBox.placeholder:GetText() == 'Bow', 'label placeholder is default label, got ' .. tostring(ui.labelBox.placeholder and ui.labelBox.placeholder:GetText()))
check(ui.labelBox.placeholder.__shown, 'placeholder visible while label empty')

-- Icons are cropped (border trimmed) in the wheel
local cropped = 0
for _, s in pairs(__texcoords or {}) do cropped = cropped + 1 end
check(cropped > 0, 'icons cropped with SetTexCoord')

-- hide settles drafts
ui.kind.macro:Click()
ui.multiBox:SetText('/e cheers wildly.'); ui.multiBox.__scripts.OnTextChanged(ui.multiBox, true)
__canvas.__scripts.OnHide(__canvas)
check(ns.DB.Wheel().slices[6].kind == 'macro' and ns.DB.Wheel().slices[6].value == '/e cheers wildly.', 'hide auto-saves valid draft')

-- ===== migration: v1 "text" slices become "/e" macros that look the same =====
JestDB = { version = 1, profiles = { Default = { wheels = { { name = 'Emotes', slices = {
	{ kind = 'text', value = 'waves a tiny flag at everyone nearby.' },
	{ kind = 'text', value = 'nods.', icon = 12345, label = 'Nod' },
	{ kind = 'emote', value = 'WAVE' },
} } } } } }
JestCharDB = { profile = 'Default' }
ns.DB.Init()
local m = ns.DB.Wheel().slices
check(JestDB.version == 2, 'DB version bumped to 2')
check(m[1].kind == 'macro' and m[1].value == '/e waves a tiny flag at everyone nearby.', 'text -> /e macro')
check(m[1].icon == [[Interface\Icons\INV_Misc_Note_01]], 'migrated slice keeps the old text icon')
check(m[1].label == 'waves a tiny flag...', 'migrated slice keeps its old label, got ' .. tostring(m[1].label))
check(m[2].icon == 12345 and m[2].label == 'Nod', 'custom icon/label preserved')
check(m[3].kind == 'emote' and m[3].value == 'WAVE', 'emote slices untouched')
ns.DB.Init()
check(m[1].value == '/e waves a tiny flag at everyone nearby.', 'migration runs once')

return fails
""" + " end")
fails = run(ns)
out = lua.globals().__out
for i in range(1, len(out) + 1):
    print("  chat>", out[i])
fl = [fails[i] for i in range(1, len(fails) + 1)]
print("FAILURES:" if fl else "Smoke test passed", *fl, sep="\n  ")
sys.exit(1 if fl else 0)
