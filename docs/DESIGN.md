# Blith design language — v4 "Signal"

Blith is an **instrument for understanding your own body**. v4 keeps v3's engineering (scores,
factors, personal ranges, evidence behind every number) and replaces its look, which read as a
generic dashboard: traffic-light colours, neon dials, identical gradient cards and dark-only.

North star: **curiosity + control + calm**. Data emerges from darkness; colour only appears where
it means something.

## Principles

1. **One story per screen.** Level 1 is one dominant thing (a score, a number with its comparison).
   Level 2 is two or three supporting facts. Level 3 is detail behind a tap.
2. **Luminance before hue.** Hierarchy must survive a greyscale screenshot. The brightest thing on a
   screen is the thing that matters; history is dim, the current range is bright, the selected
   point is brightest.
3. **The person is the baseline.** The recurring motif is a translucent *usual range* band with a
   crisp line or bar for what actually happened. Deviation is visible without maths.
4. **Status never by colour alone.** Every state is colour + glyph + words. No red/green pairs.
   Below your usual is not a failure: it is neutral, never red.
5. **Warm colour is rare and therefore loud.** One amber marker on a blue chart is the unusual day.
   Coral is reserved for heart signals and genuine alerts.
6. **Precise geometry, organic motion.** Lines, ticks and grids are exact. Motion borrows from
   breathing and pulse, and only runs to communicate state or guide attention.
7. **Plain, specific language.** "Your 30-day average is the highest in six months", never
   "You're crushing it". Numbers come from BlithCore; copy never overclaims causation.

## Colour tokens (`ios/Blith/DesignSystem/Theme.swift`, `Palette`)

Every token is adaptive (light / dark). Dark is the signature look; light is equally designed.

### Neutrals

| Token | Dark | Light | Use |
|---|---|---|---|
| canvas | #06090F | #EFF2F7 | screen background |
| surface | #0E131B | #FFFFFF | cards |
| raised | #161C26 | #F7F8FA | insets, tiles inside cards |
| sunken | #1D2431 | #E4E9F1 | tracks, empty bars, input fields |
| hairline | white 9% | #0B1220 10% | borders, separators |
| ink | #F5F7FB | #0A1120 | primary text, key numbers |
| secondaryInk | #AAB3C2 | #454E5E | supporting text |
| tertiaryInk | #828B9B | #646D7E | metadata, axis labels (AA on surface) |
| quiet | #3D4656 | #B4BDC9 | historical/context data in charts |

### Brand blue family

| Token | Dark | Light | Use |
|---|---|---|---|
| signal | #4F8EFF | #2563EB | the brand: selection, primary data, controls |
| signalBright | #7DB2FF | #1D4ED8 | selected point, current value |
| ice | #B9DAFF | #DCE9FF | soft highlight, band fills, high end of score ramp |
| deep | #1B3A8C | #1E3A8A | low end of score ramp, depth |
| cyan | #55D8E8 | #0E9FB3 | walking performance, "now", the assistant |

### Physiological palette (one hue family per signal)

| Signal | Token | Dark | Light |
|---|---|---|---|
| Movement / steps / load | signal | #4F8EFF | #2563EB |
| Walking performance | signal → cyan | | |
| Sleep | sleep (indigo) | #8587FF | #4338CA |
| Recovery / readiness | recovery (teal-cyan) | #45D0C2 | #0E7C72 |
| Heart | heart (coral) | #FF6B5E | #D63A2F |
| Weight | weight (violet, split ≥30° from sleep) | #B9A3FF | #7A4FD0 |
| Body notes (the person's own) | note (amber) | #F5B04C | #A85E07 |
| Worth a look (non-critical) | review (amber) | #F5B04C | #A85E07 |

Sleep stages are one indigo ramp (deep darkest → REM lightest); awake is the only warm stage.

### Scores

Readiness, sleep and load share one **blue luminance ramp**: low scores are deep and dim, high
scores bright and icy. The band is always also named ("High", "Moderate", "Low") and carries a glyph.
Amber appears only when a signal is outside the person's usual range.

## Type

| Role | Face | Notes |
|---|---|---|
| Hero numerals | Geist Light/Regular, tabular | tall, calm, instrument-like; scales with container |
| UI, titles | Geist | medium/semibold for titles, regular body |
| Data labels, units, eyebrows | Geist Mono | caps, +0.8 tracking, never below 11 pt |
| Interpretation sentences | New York (system serif) | one sentence that explains what a number means |

Geist and Geist Mono are bundled (SIL OFL 1.1, `Resources/Fonts`). Everything scales with Dynamic Type
except the giant numerals inside instruments.

## Surfaces and depth

canvas → surface (card) → raised (inset) → overlay (sheet) → floating (Liquid Glass bars).
In dark mode depth comes from luminance steps and a 1 px top highlight, not shadows. In light mode
cards get a soft, short shadow. Each screen has a faint atmospheric glow at the top in its signal
colour (blue for Today and Activity, indigo for Sleep, cyan for Ask). Tab bar, top bar buttons,
the chat composer and floating controls use Liquid Glass on iOS 26 (material fallback before).

## Instruments

- **ScoreDial** — a thin precise arc with a tick bezel, the usual band as a soft arc segment, the
  value as a bright arc ending in a small lit tip. Light numerals. No neon.
- **BaselineBand chart** — usual range as a translucent band, actual as a crisp line or bars,
  today/selected brightest, one amber marker for an unusual day.
- **RangeBar** — the person's range as a band with the latest reading placed on it.
- **WeekStrip** — seven bars on the blue ramp, today outlined.
- **Heatmap** — 13 weeks on the blue ramp; missing days are hollow, true zeros are filled dim.

Missing data and real zero always look different.

## Motion

- Standard easing: iOS `cubic-bezier(0.32, 0.72, 0, 1)`; reveal: `cubic-bezier(0.23, 1, 0.32, 1)`.
- Loading health data: a soft signal that breathes (expands/contracts), not a spinner.
- Insight appears: resolves from dim/blurred to sharp.
- Charts build left to right with a short cadence stagger.
- Reduce Motion replaces all of this with instant state changes.

## Custom assets

- **App icon** — see `design/app-icon.svg` (light, dark and tinted variants).
- **Symbols** — `Assets.xcassets/Symbols`, template SVGs on a 24 pt grid, preview in
  `design/symbols-preview.png`.
- **3D body** — `Resources/Body3D`, generated by `design/body3d/`. The skin is BodyParts3D (a real
  adult male scan) and the muscle layer is Z-Anatomy's, fitted to the same frame, so the layers align
  exactly: 242 named muscle parts. Both are CC BY-SA (attribution in `design/body3d/LICENSE-ASSETS.md`,
  `body3d.json` and on the Body screen). Notes anchor to regions, never screen points. The 3D stage is a
  dark imaging chamber in both appearances.
- **Fonts** — Geist and Geist Mono, SIL OFL 1.1 (`Resources/Fonts/OFL-Geist.txt`).
- **No mascot** in this phase.

## Still honest about

- Scores and the health monitor compare you with you; they are not medical assessments.
- Sleep stages come from consumer devices.
- Any anatomy shown is for orientation and notes, not diagnosis.
