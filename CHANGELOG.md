# Changelog

## Unreleased

- Dragging a slice to a new place in the editor now moves it there and shifts the slices in between along, keeping their order, instead of swapping two slices. While you drag, the other icons slide round the ring to show where everything will end up, and the target is highlighted ("Move to slot 5"). Moves can be undone.

## v0.4.0-beta

- The icon picker has a search box: type part of a name ("dance", "heart", "beer") and the grid narrows as you type. Words can be combined, and a file ID or texture path still works.
- Category chips (Abilities, Achievements, Items, All) cut the list down; it opens on Abilities, or on the current icon's category. Hover an icon to see its name.
- The icon picker has a scroll bar.
- **Reopen on last wheel** now has a checkbox next to the wheel tabs, and the wheel you were on is remembered after a reload or relog.

## v0.3.1-beta

- The editor now opens in its own movable window (`/jest`, or *Options → AddOns → Jest → Open Jest*) instead of inside the game's Settings. The game's own bags can be opened alongside it to drag things onto the wheel; before, they wouldn't open while Settings was up. Closing it no longer brings up the Game Menu.
- Appearance settings stay in *Options → AddOns → Jest → Appearance*, also reachable from the editor's **Appearance...** button.

## v0.3.0-beta

- **Multiple wheels**, optional: add up to 5 with the **+** tab in the options, then scroll the mouse wheel while the wheel is open to switch between them (works in combat). The wheel's name and a dot per wheel show above it.
- Wheel tabs: click to edit, double-click to rename, right-click to rename, move or delete (with Undo).
- New setting *Reopen on last wheel used* (off by default: the wheel always opens on the first wheel).
- `/jest wheel` lists wheels; `/jest wheel <n>` picks the one other commands edit; `/jest wheel add|rename|remove`.

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
