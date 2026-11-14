# Jest

A radial wheel for **WoW: Forever**: emotes, potions, spells and more. Hold a key, flick the mouse toward a slice, release. Works in combat.

> **Alpha.** Please [report issues here](https://github.com/bryn-ph/jest/issues).

## Features

- Hold-to-open wheel with up to 12 slices; release to fire, release in the centre to cancel.
- Slices can be any of the game's emotes, a macro (use `/e` for a custom emote line), or anything you can drag: items and consumables, spells, mounts, toys, battle pets and equipment sets.
- Drag things straight from your bags or spellbook onto the wheel in the options. Item slices show how many you have left.
- Emotes are tagged **Anim** and/or **Voice** for your character, with filters to find them.
- Number keys fire slices while the wheel is open; a second key repeats the last one.
- Options panel with a live preview: drag slices to rearrange, pick icons and labels, set key bindings.
- Settings are saved account-wide.


## Usage

1. Open the options with `/jest` (or *Options → AddOns → Jest*) and set the **Open wheel** key.
2. Hold the key, move the mouse toward a slice, and release.

| While the wheel is open | |
|---|---|
| Release in the centre, or `Esc` | Cancel |
| `1`–`9`, `0` | Fire that slice |

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
