# Jest

A radial wheel for **WoW: Forever**. Put anything on it: potions and food, spells, mounts, toys, battle pets, equipment sets, macros and emotes. Hold a key, flick the mouse toward a slice, release. Works in combat.

Use it as a quick-access menu for the things you don't want on your action bars, as an emote wheel for roleplay, or both, with a wheel for each.

> **Beta.** Please [report issues here](https://github.com/bryn-ph/jest/issues).

## Features

- Hold-to-open wheel with up to 12 slices; release to fire, release in the centre to cancel.
- Slices can be anything you can drag: items and consumables, spells, mounts, toys, battle pets, macros and equipment sets. Or any of the game's emotes, or your own macro text (use `/e` for a custom emote line).
- Drag things straight from your bags, spellbook or collections onto the wheel in the options. Item slices show how many you have left.
- Optional extra wheels (up to 5): scroll the mouse wheel while it's open to flip between them, e.g. consumables on one, mounts on another, emotes on a third.
- Emotes are tagged **Anim** and/or **Voice** for your character, with filters to find them.
- Number keys fire slices while the wheel is open; a second key repeats the last one.
- Editor window with a live preview: drag slices to rearrange, pick icons and labels, set key bindings. It stays open alongside your bags.
- Icon picker with search: type "dance" or "beer" to find an icon by name, filtered to Abilities, Achievements, Items or All.
- Settings are saved account-wide.


## Usage

1. Type `/jest` to open Jest's window (also under *Options → AddOns → Jest*) and set the **Open wheel** key.
2. Hold the key, move the mouse toward a slice, and release.

| While the wheel is open | |
|---|---|
| Release in the centre, or `Esc` | Cancel |
| `1`–`9`, `0` | Fire that slice |
| Mouse wheel | Switch to the next or previous wheel (with more than one) |

To add a wheel, click **+** next to the wheel tabs in the options. Double-click a tab to rename it, or right-click it to rename, reorder or delete it. By default the wheel always opens on the first wheel, so directions stay the same; *Appearance → Reopen on last wheel used* changes that.

Changes made in combat apply when combat ends. `/jest help` lists the slash commands.

## Known limitations

- Voice lines on WoW: Forever depend on race. The **Voice** tag reflects your current character.
- Emotes can't be sent in some instance situations where the game restricts chat.
- Macro slices are limited to 255 characters, like any macro.
- English only for now.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Code: [MIT](LICENSE).

The icon is based on [Jester Hat](https://game-icons.net/1x1/delapouite/jester-hat.html) by Delapouite, from [game-icons.net](https://game-icons.net), licensed [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). It has been recoloured and framed.
