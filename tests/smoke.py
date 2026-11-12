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
  setmetatable(o, { __index = function(t, k) return m[k] or function() end end })
  return o
end
_G.newObj = newObj
UIParent = newObj("UIParent")
CreateFrame = function(_, name, _, _) local f = newObj(name); if name then _G[name] = f end; return f end
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
for _, fn in ipairs({ ns.DB.Init, ns.SecureWheel.Apply }) do fn() end
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
return fails
""" + " end")
fails = run(ns)
out = lua.globals().__out
for i in range(1, len(out) + 1):
    print("  chat>", out[i])
fl = [fails[i] for i in range(1, len(fails) + 1)]
print("FAILURES:" if fl else "Smoke test passed", *fl, sep="\n  ")
sys.exit(1 if fl else 0)
