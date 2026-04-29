# Flip-clock animation extension

Adds a real change-driven flip-card animation on top of the upstream
html-clock-plasmoid. The widget renders pre-rendered PNG frames per digit
pair via `<img src>`, and a tiny QML extension introduces three new
placeholders that pick the correct frame based on the wall clock.

## What changed in the plasmoid

Three new placeholders are added — they return an integer 0..25 that
indexes into the frame set:

### Per-pair flip frames (animate at the boundary regardless of which digit changes)

| Placeholder | Animates in the last 400ms before |
|---|---|
| `{hh-flip}` | the next hour boundary |
| `{ii-flip}` | the next minute boundary |
| `{ss-flip}` | the next second boundary |
| `{dd-flip}` | midnight (day of month) |
| `{mm-flip}` | the next month boundary |
| `{yyyy-flip}` | January 1st of next year |

### Per-digit value & flip placeholders (compose multi-digit values from a single 0..9 set)

| Value | Flip | Notes |
|---|---|---|
| `{h1}` `{h2}` | `{h1-flip}` `{h2-flip}` | hour, tens / units |
| `{i1}` `{i2}` | `{i1-flip}` `{i2-flip}` | minute |
| `{s1}` `{s2}` | `{s1-flip}` `{s2-flip}` | second |
| `{d1}` `{d2}` | `{d1-flip}` `{d2-flip}` | day of month |
| `{m1}` `{m2}` | `{m1-flip}` `{m2-flip}` | month number |
| `{y1}` `{y2}` `{y3}` `{y4}` | `{y1-flip}` … `{y4-flip}` | year, thousands → units |

Per-digit flips animate **only when that specific digit's value will
change at the next tick** — e.g. at 19:59:59.6 both `{h1-flip}` and
`{h2-flip}` animate (1→2, 9→0), but at 14:59:59.6 only `{h2-flip}`
animates because the tens-of-hour digit stays at "1".

All flips return `0` (rest) outside their animation window.

A `{home}` placeholder expands to the current user's home directory so
absolute image paths can be portable across users.

The animation is predictive: it computes `msUntilNextTick` from the wall
clock and renders frames 1..25 in the last 400ms of the tick window,
landing exactly at the boundary. The new value then takes over at frame
0 (rest). No prev-value tracking is needed.

A dedicated 16ms timer (`flipFrameTimer`) drives ~60fps redraws,
independent of the user's `Cycle interval` setting.

### Files touched

- `src/contents/ui/HtmlClock.qml` — runtime: `flipFrameTimer`,
  `handleFlipFrame()`, `flipFrameAnimMs`, `flipFrameCount`
- `src/contents/ui/config/Layout.qml`,
  `src/contents/ui/config/Layout2.qml`,
  `src/contents/ui/config/Layout3.qml` — preview pipeline mirrors the
  runtime so the live preview animates identically

## Frame generator

`tools/gen_flip_frames.py` produces:

- `~/.local/share/html-clock-flip/n/` — 10 single-digit values (0..9, wrap to 0), 26 frames each → 260 PNGs
- `~/.local/share/html-clock-flip/sep/colon.png` — static `:` separator card (half-width)
- `~/.local/share/html-clock-flip/sep/slash.png` — static `/` separator card (half-width)

The single 0..9 set covers hours, minutes, seconds, days, months and
years just by stacking `<img>` tags. Separators are static (don't
animate) and rendered at half the digit width so they compose nicely.
Old per-pair sets (`h/`, `ms/`, `dd/`, `mm/`) are removed on re-run.

26 frames per value (frame 0 = rest, frames 1..25 = the rotation curve):

- Static back: top half of NEXT digit (revealed as the upper flap rotates
  past 0°)
- Static lower: bottom half of CURRENT digit (covered as the underside
  lands past 90°)
- Rotating flap: angle follows `π·t²` (ease-in-quadratic). At 0° shows
  CURRENT top compressed; at 180° shows NEXT bottom underside, fully
  covering the lower static
- Hairline at the card seam, drawn on every frame
- Rounded corners (radius 8px) via PIL alpha mask

Run with defaults (120×100 cards, DejaVu Sans Mono Bold, radius 8):

```bash
python3 flip-clock/tools/gen_flip_frames.py
```

Or customize size, font, corner radius:

```bash
python3 flip-clock/tools/gen_flip_frames.py \
    --width 160 --height 140 \
    --font /usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Bold.ttf \
    --radius 12
```

CLI flags:

| Flag | Default | Notes |
|---|---|---|
| `--width` | 120 | card width (px) |
| `--height` | 100 | card height (px) |
| `--font` | DejaVu Sans Mono Bold | path to a TTF |
| `--radius` | 8 | rounded-corner radius (0 = sharp) |
| `--font-size` | 76% of `--height` | digit font size |
| `--out` | `~/.local/share/html-clock-flip` | output root |

Outputs ~2184 PNGs (~9MB at default size).

## Layout

`flip-clock/layout.html` — paste into the widget's User Layout tab.

The layout references frames under `{home}/.local/share/html-clock-flip/`.
The widget expands `{home}` to the current user's home directory at render
time (resolved via `QtCore.StandardPaths.HomeLocation`), so the same template
works for any user.

## Cycle interval

The user-facing `Cycle interval` setting in the widget is irrelevant for
this animation — the dedicated `flipFrameTimer` handles it. Default value
(typically 1000ms) is fine.
