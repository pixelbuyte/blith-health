# Blith design language

Blith v3 is a **precision instrument for your own body**. Like WHOOP, it's dark, dense and exact:
three daily scores on glowing dials, a health monitor of personal ranges, and every number one tap
away from the factors behind it. From Skintel it takes an editorial layer: serif sentences that
interpret, mono data labels, bento tiles, accent-barred callouts, a 7-day strip, a heatmap and a
"why this verdict" list with confidence labels.

## What changed from v2

| Area | v2 | v3 |
|---|---|---|
| Canvas | Light paper with a cobalt wash; dark mode as an afterthought | Near-black `#07080B` only, like an instrument. A soft glow at the top of each screen takes that screen's signal colour, such as the readiness band on Today. |
| Today | A step story card | **Sleep, Readiness and Load dials**, a 7-day readiness strip, a **Health Monitor** (resting heart rate, HRV, respiratory rate, blood oxygen and wrist temperature against *your* range), movement at the same time of day, then the evidence-backed insight |
| Tabs | Today · Walk · Body · Ask | Today · Activity · **Sleep** · Body · Ask |
| Sleep | A sheet with a timeline | A full tab: performance against personal need, stages with shares, efficiency, time to fall asleep, wake-ups, consistency, 7-night debt, a "tonight" suggestion, timing and a 13-week heatmap |
| Activity | Walking ranges | A **Load** dial (0–10, logarithmic) with your usual band, its factors and workouts, and a 13-week load heatmap, above the step ranges, gait and walking signature |
| Body | A flat 2D SVG that could only flip | A **real 3D male figure** (SceneKit) with free turntable rotation, pinch zoom, tap-to-select regions, 3D note markers with dates, and a **Muscles** layer |
| Mascot | Bli on six screens | Removed for now |
| Icon | Soft blue tile | Black instrument tile; the "b" is a gauge whose glowing tip is the needle |

## Tokens (`ios/Blith/DesignSystem/Theme.swift`)

| Token | Meaning | Hex |
|---|---|---|
| canvas / surface / raised | background / cards / insets | #07080B / #101217 / #181B22 |
| ink / secondary / tertiary | text | #F2F4F8 / #8A90A0 / #565C6B |
| mint · amber · coral | readiness bands: high (67+) · moderate (34–66) · low (≤33) | #34E0A1 · #FFB547 · #FF5E57 |
| cobalt | movement and load, the brand | #4C8DFF |
| cyan | "now", highlights, the assistant | #3DDCFF |
| violet (`sleep`) | sleep | #9B8CFF |
| rose (`heart`) | heart signals | #FF4D6D |
| orange (`note`) | the person's own body notes | #FF8A4C |

**Type:**

- Scores and hero values use condensed **SF Pro** (`Typo.score`, `.compressed`), the tall instrument numerals.
- Section heads are expanded heavy caps (`SectionHeader`).
- Data labels use SF Mono caps (`Eyebrow`, `MonoPill`).
- Sentences that interpret use the New York serif (`Typo.story`, `Typo.display`).

**Motion:**

- Easing is iOS `cubic-bezier(0.32, 0.72, 0, 1)` (`Motion.standard`), plus a longer reveal curve (`Motion.reveal`).
- Dial arcs draw to their value on appear.
- Reduce Motion is respected everywhere.

## Instruments (`DesignSystem/Instruments.swift`)

- **ScoreDial**: a 300° gauge with ticks, a gradient arc, a glow, a needle knob and an optional "usual" band.
- **FactorRow** + **DivergingMeter**: one factor per row. It shows the value, your usual, a centred meter for which way the factor pulled, and its share of the score.
- **RangeBar**: your personal range as a band, with the latest reading placed on it.
- **WeekStrip**: seven readiness bars, today outlined, tappable (Skintel's 7-day strip).
- **ScoreHeatmap**: 13 weeks, Monday-first, for readiness, sleep or load (Skintel's journal heatmap).
- **MetricTile**: a bento tile with a mono label, a condensed numeral and a sparkline.
- **MonoPill**, **SegmentedProgress**.

## Scores (`BlithCore/Analytics/Scores.swift`)

All scores are relative to the person's own history and always shown with their factors.

- **Readiness 0–100.** It needs 14 nights of heart data before it scores; until then the dial shows "Calibrating n/14".
  - HRV against your 30-day log-baseline: 50%.
  - Resting heart rate against its baseline: 20%.
  - Sleep performance: 30%.
  - −5 when respiratory rate is well above your usual.
- **Sleep performance 0–100.**
  - Hours against your personal need: 55%. Need is the 75th percentile of your last 28 nights, kept between 7 and 9 h.
  - Efficiency: 15%.
  - Deep + REM share: 15%.
  - Bedtime consistency against your last 7 nights: 15%.
- **Load 0–10.** A logarithmic scale of active energy + 4 × exercise minutes. It is shown against the middle half of your last 28 days.
- **Health Monitor.** Each vital is compared with your 30-night mean ± 1.5 SD. A reading outside that range is never presented as a diagnosis.

## Custom assets

- **App icon** (`design/app-icon.svg`, plus dark and tinted variants).
- **Symbols** (`Assets.xcassets/Symbols`, preview `design/symbols-preview.png`). 42 glyphs on a 24 pt grid with a 2.0 stroke and round caps, as template SVGs. The tab icons have filled variants. The body glyphs are an athletic male V-taper.
- **3D body** (`Resources/Body3D`, generated by `design/body3d/build_body.py`).
  - **Source:** MakeHuman's CC0 base mesh with male, muscular, ideal-proportion targets. The assets are CC0 1.0, and so is the output.
  - **Regions:** triangles are grouped into the 33 `BodyRegion`s. Each region is its own SceneKit element, so a tap returns the region directly, and notes are anchored to regions, never to screen points.
  - **Figure look:** a deep cobalt Lambert surface with a Fresnel rim, cyan anatomy lines baked into `body_detail.png`, a bloom and a slowly sweeping key light.
  - **Muscles layer:** `body_muscle.jpg` is baked in the mesh's UV space from 3D fibre directions per muscle group, so seams stay continuous. It is an illustrative map of the main surface groups, not an anatomical atlas.

## Interactions

- Every dial opens its detail: Sleep → Sleep tab, Readiness → readiness sheet, Load → Activity.
- Every vital row opens its 30–60 day chart with your range band.
- Heatmap cells and strip bars select that day.
- **Body:**
  - Horizontal drag turns the figure; vertical drags still scroll the page. Pinch zooms.
  - There are Front, Side and Back shortcuts.
  - Tapping a region highlights it and opens its panel. On the Muscles layer, the panel names the muscle group.
  - Selecting a note turns the figure to face that region, zooms in, and shows a 3D label with the date.
  - The timeline shows which notes were unresolved on a chosen date.
  - A region list is the accessible alternative to tapping.

## Still honest about

- The muscle layer is illustrative, not reviewed anatomy.
- The Health Monitor and the scores are comparisons with you, not medical assessments.
- Sleep stages come from consumer devices.
