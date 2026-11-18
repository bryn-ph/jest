# Changelog

## Unreleased

- **A cleaner, native-looking window.** Jest's window is now a standard game window, like the Collections or Character windows: the Jest portrait and title, the game's own close button, inset panels and text boxes. Its bottom tabs split it into **Wheels** (your wheels and the slice editor) and **Options**. Your wheels sit as tabs along the top of the Wheels page, and the Profile dropdown is in the top bar.
- Settings moved into the **Options** tab: key bindings, ring radius, cancel zone, scale, scrolling, reopening on the last wheel, sounds and the minimap button. The *Appearance* page in the game's Settings is gone; *Options → AddOns → Jest* still opens Jest.
- The icon picker and the name prompt use the same native window style.
- **Cooldowns on the wheel.** Items, toys and spells show a cooldown swipe and the time left, live while the wheel is open.
- Fixed: mount slices didn't summon (e.g. a paladin's Summon Warhorse). Mounts now summon through the mount journal, whether dragged from the journal or the spellbook, and firing the mount you're on dismounts.
- Fixed: a left click then a quick right click on a wheel tab started renaming it; it now opens the menu. Only a double left click renames.

## v0.5.0-beta

- **Profiles.** Each new character now starts with a fresh profile of its own (named "Character - Realm") instead of inheriting another character's wheels. Characters you already use keep the shared "Default" profile.
- The editor's new **Profile** dropdown (top right) lists your profiles: click one to switch, **×** to delete it (even the one you're on), or **+ New profile...**. The **...** button next to it renames this profile, copies another profile's wheels and settings into it, or resets it. Copy, reset and delete can be undone. Renaming a profile keeps every character that uses it.
- `/jest profile` lists profiles; `/jest profile <name>` switches; `/jest profile new|copy|rename|delete`.
- **Minimap button.** Click it to open the editor; drag it round the minimap's edge to move it. Hide it under *Appearance → Minimap button* or with `/jest minimap`.
- Switching wheels now takes two notches of the mouse wheel, so a stray scroll doesn't change wheels. Change it under *Appearance → Scroll to switch wheels* (1–5) or with `/jest scrollsteps`.
- Fixed: the wheel tab right-click menu was missing its background.

## v0.4.1-beta

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

- Slices can now hold anything you can drag: items and consumables, spells, mounts, toys, from your bags, spellbook or collections onto the wheel preview: drop on a slice to replace it (with Undo), or in the centre to add one. The editor has a new **Action** tab with its own drop box.
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
