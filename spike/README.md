# JestSpike: feasibility spike

This is a throwaway addon. It checks that the core idea of Jest works on WoW: Forever before any real code gets written. The check numbers (S1–S7) match §8 of the plan.

## Install
Link the folder into the client's AddOns directory. Run this in **Windows PowerShell** and change `$wow` to match your install. A junction doesn't need admin rights:

```powershell
$wow = "G:\GAMES-NVME\Blizzard\World of Warcraft\_forever_"
New-Item -ItemType Junction -Path "$wow\Interface\AddOns\Jest" -Target "C:\Users\brynp\projects\jest\Jest"
```

To remove it later, delete only the link (the repo files stay): `(Get-Item "$wow\Interface\AddOns\JestSpike").Delete()`

Restart the client fully (a new addon isn't picked up by `/reload`). Then:
- turn on `/console scriptErrors 1`, or install BugSack;
- bind **"Spike: hold to open wheel"** and **"Spike: repeat last slice"** in *Options → Keybindings → AddOns → Jest (spike)*.

## Slice layout (4 slices, clockwise from the top)
| Slice | Direction | Path | Action |
|---|---|---|---|
| 1 | up | macrotext | `/dance` |
| 2 | right | macrotext | `/e waves (macro path).` |
| 3 | down | custom type | `C_ChatInfo.PerformEmote("CHEER")` |
| 4 | left | custom type | `SendChatMessage(..., "EMOTE")` |

## Checks
| # | Do | Pass when |
|---|---|---|
| S1 | Log in, then run `/jestspike info` | Not flagged "out of date" in the AddOns list. Note the printed `interface =` value and `WOW_PROJECT_ID`. |
| S2 | Hold the wheel key, then release it | `down=true` prints on press and `down=false` on release |
| S3 | Hold, move up, release | You **dance on release**, and nothing happens on press |
| S4 | Repeat S3 at a target dummy **in combat** in all 4 directions | The red dot appears at the cursor, the printed slice matches the direction, and the actions fire. The `[R5]` line says `match`. |
| S4b | Release without moving | "dead zone -> cancel" prints and nothing fires |
| S4c | Hold right mouse (mouselook), press the wheel key, let go of right mouse, aim, release | Note what happens and what `mouselooking =` prints |
| S5 | Open the wheel, then press `1`–`4`. Open again and press Esc. Then press the repeat key. In and out of combat. | The number key fires its slice and Esc cancels. Afterwards `1`–`4` and Esc behave normally again. Repeat fires the last slice. |
| S6 | Fire slices 2, 3 and 4: outdoors, in a dungeon, and after `/console addonChatRestrictionsForced 1` (reset with `0`) | Record which paths work where, and the `[S6]` output |
| S7 | `/jestspike dump` | All 8 default tokens show `ok`. Note which candidate icons render (an icon, not a green box) and have non-nil fileIDs. |

Paste the chat output back, or a summary of it. If S3 or S4 fails in combat, we switch to the fallback architecture (plan §2 Q1).
