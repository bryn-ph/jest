# Contributing

## Setup

The addon lives in `Jest/`. Link it into the client instead of copying (PowerShell; adjust `$wow`):

```powershell
$wow = "C:\Program Files (x86)\World of Warcraft\_forever_"
New-Item -ItemType Junction -Path "$wow\Interface\AddOns\Jest" -Target "$PWD\Jest"
```

`/reload` picks up Lua changes. New files, TOC edits and new media need a full client restart.

## Layout

| Path | |
|---|---|
| `Jest/Core/` | Namespace and events, saved variables (validation and migrations), emote data and helpers |
| `Jest/Secure/` | Protected frames and the restricted snippet. This is what fires slices, including in combat. |
| `Jest/UI/` | Wheel drawing (`WheelView`, shared with the options preview), the in-game wheel (`Skin`), geometry |
| `Jest/Config/` | Options panel, popups, widgets and slash commands |
| `tools/` | Generators for the wheel art and emote data |
| `tests/` | Offline tests that run the addon against a mocked WoW API |

Two invariants to keep:

- `Geometry.SliceAt` (UI/Geometry.lua) and the maths in `Secure/Snippets.lua` must stay identical. With `/jest debug` on, every fire reports whether they agreed.
- Nothing may change secure attributes or bindings during combat. `SecureWheel.Apply` defers itself until combat ends.

## Tests

```powershell
python -m venv .venv
.venv\Scripts\pip install -r requirements-dev.txt
.venv\Scripts\python tests\check.py   # Lua 5.1 syntax (addon + secure snippet), geometry
.venv\Scripts\python tests\smoke.py   # loads the addon against a mocked API and exercises it
```

CI runs both on every push and pull request, and builds the release zip without uploading it (see the run's artifacts).

## Generated files

- `Jest/Core/EmoteData.lua`: emote animation and voice data from WoW: Forever's game tables (via wago.tools). Regenerate after a patch with `tools\gen_emote_data.py`, or pin a build with `--build <version>`.
- `Jest/Media/icon.tga` and `assets/logo.png`: the addon icon, from `tools\gen_icon.py` (source art in `assets/`, CC BY 3.0, see README).
- `Jest/Media/wedge_*.tga`: wheel segment art from `tools\gen_wedges.py`. Add `--preview preview.png` to render a sample wheel. Its geometry constants must match those at the top of `Jest/UI/WheelView.lua`.

## Debugging

- `/jest debug` for Jest's own messages.
- `/console scriptErrors 1`, or BugSack, to see Lua errors.
- `/fstack` (frames under the cursor) and `/etrace` (events).
- `/console taintLog 1`, then read `_forever_\Logs\taint.log`, for "action blocked" problems.

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) from `.pkgmeta`. The TOC's `@project-version@` is replaced with the tag.

1. Update `CHANGELOG.md`.
2. Tag and push, e.g. `git tag v0.1.0-alpha && git push origin v0.1.0-alpha`. Tags containing `alpha` or `beta` are published as that release type.

Uploading needs the repository secrets `CF_API_KEY` (CurseForge) and `WAGO_API_TOKEN` (Wago), plus the project IDs as `## X-Curse-Project-ID` and `## X-Wago-ID` in `Jest/Jest.toc`. Without them, the release is only attached to GitHub.
