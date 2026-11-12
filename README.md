# Jest

A hold-to-open radial emote wheel for **WoW: Forever** (interface 16001). Hold the key, flick the mouse toward an emote, then release. It works in combat.

## Install (development)
Link the addon folder into the client from **Windows PowerShell**. Change `$wow` to match your install:

```powershell
$wow = "C:\Program Files (x86)\World of Warcraft\_forever_"
New-Item -ItemType Junction -Path "$wow\Interface\AddOns\Jest" -Target "C:\Users\brynp\projects\jest\Jest"
```

Restart the client once so it sees the new addon. After that, `/reload` picks up Lua edits. New files and TOC changes still need a restart.

Bind **Open emote wheel (hold)** and **Repeat last emote** under *Options → Keybindings → AddOns → Jest*.

## Using it
| Action | Result |
|---|---|
| Hold the key, aim, release | Fires the highlighted slice |
| Release in the centre | Cancels |
| Number keys `1`–`9`, `0` while open | Fires that slice |
| `Esc` while open | Cancels |
| Repeat key | Re-fires the last slice, without opening the wheel |

### Options panel
Open it with `/jest` (alias `/ew`), from *Options → AddOns → Jest*, or from the minimap addon-compartment menu.
- **Jest page:**
  - Set the wheel key and the repeat key: click the button, then press a key. Right-click clears it.
  - Edit the slices: pick a type (Emote, Text or Macro), type the action and click Save (Enter also saves emote and text slices).
  - For emotes, matches appear as you type. The arrow keys move through them, and Enter, Tab or a click picks one, which saves it.
  - Optionally set a label (the default shows in grey inside the box) and choose an icon from the picker.
  - A live preview of the wheel, drawn with the same code as the in-game wheel, shows where each slice sits. Click a slice to edit it, or drag it onto another slice to swap them; dropping in the centre cancels. Add and Remove sit above it. `/jest move` still works from chat.
  - Test performs an emote or text slice immediately.
- **Appearance page:** ring radius, cancel-zone size, wheel scale and sounds.

### Slash commands
`/jest help` lists every command. For example:

```
/jest list
/jest set 3 emote /roar
/jest set 4 text waves a tiny flag.
/jest set 5 macro /cast Hearthstone
/jest icon 3 Ability_Druid_ChallangingRoar
/jest emotes ro
```

Edits made in combat are queued and apply when combat ends.

## Layout
| Path | Role |
|---|---|
| `Jest/Secure/` | Protected frames and the restricted-Lua click snippet. This part decides what fires. |
| `Jest/UI/Skin.lua` | Visuals, highlight, animation and sound. Insecure and advisory only. |
| `Jest/UI/Geometry.lua` | Slice math. It **must** match the copy in `Secure/Snippets.lua`. |
| `Jest/Core/` | Namespace, SavedVariables and profiles, emote discovery, slice helpers |
| `Jest/Config/Panel.lua` | Options panel (Settings API): key capture, slice editor, Appearance sliders |
| `Jest/Config/IconPicker.lua` | Icon picker popup |
| `Jest/Config/Slash.lua` | `/jest` commands |
| `spike/` | The original feasibility spike, kept for reference |

## Offline tests
These need no game client. They use Lua 5.1 through `lupa`:

```powershell
python -m venv .venv; .venv\Scripts\pip install -r tests\requirements.txt
.venv\Scripts\python tests\check.py   # syntax-check all Lua + the secure snippet, geometry tests
.venv\Scripts\python tests\smoke.py   # load the addon against a mocked WoW API, exercise slash/skin/secure paths
```

## Wheel art
The slice segments in `Jest/Media/wedge_<N>.tga` (and `_glow`) are generated, one pair for each slice count from 2 to 12. Each is drawn pointing up and rotated into place in-game. To change their shape, edit `tools/gen_wedges.py`. The geometry constants must match the ones at the top of `Jest/UI/Skin.lua`. Then regenerate:

```powershell
.venv\Scripts\pip install -r tools\requirements.txt
.venv\Scripts\python tools\gen_wedges.py --preview preview.png   # preview.png shows an 8-slice wheel
```

The client only notices new or changed media files after a full restart, not a `/reload`.

## Debugging in-game
- `/jest debug` prints the slice the secure code picked and the slice the skin highlighted on every fire. A `MISMATCH` means the two geometry copies have drifted.
- Turn on `/console scriptErrors 1`, or install BugSack.
- `/fstack` shows which frames are under the cursor.
- `/etrace` opens a live event log.
- For taint problems, run `/console taintLog 1` and then read `_forever_\Logs\taint.log`.
