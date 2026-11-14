# Changelog

## v0.2.0-alpha

- Slices can now hold anything you can drag: items and consumables, spells, mounts, toys, battle pets, macros and equipment sets. They fire in combat wherever the game allows.
- Drag things from your bags, spellbook or collections onto the wheel preview: drop on a slice to replace it (with Undo), or in the centre to add one. The editor has a new **Action** tab with its own drop box.
- Item slices show how many you have; they grey out at zero.
- `/jest set <n> item|spell|toy <id>`.
- Fixed: long macro text no longer spills out of the editor box; it scrolls instead.
- The hovered slice's name now shows in a caption under the wheel instead of squeezed into the centre, so long item names fit. The centre icon is larger.

## v0.1.0-alpha

First public alpha.

- Hold-to-open radial wheel: aim and release to fire, release in the centre or press Esc to cancel. Works in combat.
- Slices are emotes (picked from a searchable list, tagged Anim / Voice) or macros (`/e` for custom emote lines).
- Number keys fire slices while the wheel is open; a separate key repeats the last one.
- Options panel with a live wheel preview: drag slices to rearrange, choose icons and labels, set key bindings.
- Appearance settings: ring radius, cancel zone, scale, sounds.
- `/jest` slash commands for everything in the panel.
