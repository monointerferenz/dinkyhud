# dinkyhud

A [Hammerspoon](https://www.hammerspoon.org) Spoon that renders a compact floating HUD
for the [`dinky`](https://github.com/mikker/Dinky) tiling window manager: one segment per workspace with a
[sketchybar-app-font](https://github.com/kvndrsslr/sketchybar-app-font) icon for each app, the focused workspace highlighted, and a badge
for the current layout/mode. It refreshes on a timer and immediately when Spaces
change or applications launch/quit.

![](https://github.com/monointerferenz/dinkyhud/blob/doc/doc/dinkyhud.png?raw=true)

## Requirements

- macOS with [Hammerspoon](https://www.hammerspoon.org)
- `dinky` — defaults to `/opt/homebrew/bin/dinky` (override with `dinkyhud.dinkyBin`)
- The `sketchybar-app-font` font for the app icons (unknown apps fall back to `:default:`)

## Install

Copy (or symlink) the spoon into your Hammerspoon config:

```bash
cp -R dinkyhud.spoon ~/.hammerspoon/Spoons/
# or, while developing:
ln -s "$(pwd)/dinkyhud.spoon" ~/.hammerspoon/Spoons/
```

## Usage

```lua
-- ~/.hammerspoon/init.lua
hs.loadSpoon("dinkyhud")

-- optional: configure before start()
spoon.dinkyhud.position = "top"

spoon.dinkyhud:start()
```

`hs.loadSpoon` calls `:init()` automatically (it creates the canvas); you are
responsible for calling `:start()`.

## Configuration

Set these between `hs.loadSpoon("dinkyhud")` and `spoon.dinkyhud:start()`:

| Variable         | Default                      | Description                                              |
| ---------------- | ---------------------------- | -------------------------------------------------------- |
| `dinkyBin`       | `/opt/homebrew/bin/dinky`    | Absolute path to the `dinky` executable                   |
| `appFont`        | `sketchybar-app-font`        | Font used for the app icons                               |
| `position`       | `"bottom"`                   | `"bottom"` (above the Dock) or `"top"` (below menu bar)   |
| `refreshInterval`| `2`                          | Seconds between automatic refreshes                       |
| `iconMapPath`    | bundled `icon_map.sh`        | Path to the sketchybar app icon map                       |
| `layoutLabels`   | `dwi` / `mst` / `scr`        | Short label per layout (`dwindle`, `master`, `scrolling`) |
| `modeColors`     | blue / amber / lavender      | Badge colour per dinky mode; `default` is the fallback    |

## Methods

| Method            | Description                                                        |
| ----------------- | ------------------------------------------------------------------ |
| `:init()`         | Create the HUD canvas (called automatically by `hs.loadSpoon`)      |
| `:start()`        | Show the HUD, start the refresh timer and the Spaces/app watchers   |
| `:stop()`         | Stop the timer and watchers, hide the HUD                           |
| `:update()`       | Refresh the HUD immediately (normally not needed)                   |

## Repository layout

```
dinkyhud.spoon/
├── init.lua      # the Spoon itself
├── icon_map.sh   # sketchybar-app-font ligature map (bundled resource)
├── meta.json     # metadata read by hs.loadSpoon (spoon.spoonMeta)
└── docs.json     # generated console documentation (hs.doc)
```

### Regenerating docs

`docs.json` is generated from the `---` doc comments in `init.lua`:

```bash
hs -c "hs.doc.builder.genJSON('$(pwd)/dinkyhud.spoon')" > dinkyhud.spoon/docs.json
```

(the `hs` CLI requires `require("hs.ipc")` in your config; alternatively run
`hs.doc.builder.genJSON("<path to dinkyhud.spoon>")` from the Hammerspoon console
and save the result to `docs.json`).
