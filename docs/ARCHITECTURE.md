# Blith — architecture

Blith turns a person's health history into personalized understanding. Everything the user
sees is derived from deterministic calculations on their own data; the AI explains results,
it never computes them.

## Audit (starting point)

The repository was greenfield (a one-line README). There was no existing app, navigation,
persistence or design system to preserve, so native SwiftUI was chosen because HealthKit is
central. Build, signing and CI conventions were borrowed from the sibling Skintel project
(XcodeGen + Codemagic, no local Mac), along with its App Store checklist habits.

## Layers

```
HealthDataProvider  ── AppleHealthProvider (HealthKit, app target)
  (BlithCore)        ── MockHealthProvider  (deterministic demo scenarios)
                     ── HuaweiHealthProvider (cloud REST adapter, inactive until configured)
        │  ProviderBatch: normalized DailyAggregate / HourlyBuckets / HealthSample /
        │                 SleepSegment / WorkoutRecord, each with SourceRef provenance
        ▼
Normalization        SleepAssembler (one source per night), SourceMerger (cross-provider dedup)
        ▼
SyncEngine           initial import (recent 120 days first, then yearly chunks back up to 5 years),
                     incremental sync (re-reads from 2 days before last sync; days are replaced,
                     never added, so re-syncs are idempotent), retry with backoff
        ▼
LocalHealthStore     HealthHistory JSON per data origin (Apple Health vs each demo scenario),
                     complete file protection on iOS
        ▼
HealthAnalytics      averages, personal baselines, same-weekday "usual by now", period summaries,
WeightAnalytics      weekday / time-of-day patterns, consistency, personal bests, anomalies,
SleepAnalytics       correlations; EWMA weight trend; sleep summaries
        ▼
InsightEngine        13 detectors → quality filter (magnitude + data sufficiency) → ranking
                     (score, goal relevance, one per family, max 4) with evidence rows
        ▼
HealthSnapshot       everything the three tabs render, built once per sync off the main thread
        ▼
HealthAssistantTools 17 deterministic tools (OpenAI function-calling schema) + show_widget
LLMAssistant         OpenRouter tool loop (≤5 rounds) → ChatMessage { text, blocks, evidence }
LocalAssistant       on-device intent → same tools → templated answer (no key / no consent / offline)
        ▼
SwiftUI              Today · Walk · Ask, detail sheets, AppRouter deep links
```

`BlithCore` depends only on Foundation, so every calculation is unit-tested on Linux and in CI
(`swift test`, 41 tests). The app target holds HealthKit, SwiftUI and persistence glue only.

## Key decisions

| Decision | Why |
|---|---|
| Days keyed by `LocalDate` (day number arithmetic) | Totals belong to the day the user lived; no DST or UTC off-by-one. |
| Days with no samples are *missing*, never zero | A day without an iPhone is not a day without walking. |
| Averages exclude today | Today is partial; "7-day average" = last 7 complete days. |
| "Usual by now" = median cumulative steps at this minute on the last 8 same weekdays (≥3), else last 28 days | Compares today with *your* Tuesday, not a population. |
| Consistency threshold = step goal, or 85% of 28-day median | No fake score; the rule is stated on screen. Missing a day resets nothing. |
| Weight trend = EWMA, 7-day time constant, time-aware for gaps | Filters water-weight swings; direction needs ≥0.3 kg over 30 days. |
| Sleep night = segments ending before 6 PM on the wake date; one source per night (staged source preferred) | Avoids adding phone + watch sleep. |
| HealthKit cumulative totals via statistics collection queries | Apple's own source-priority merge; no double counting of iPhone + Watch. |
| Cross-provider merge takes the max per hour/day, never the sum | A Huawei watch syncing to Apple Health *and* read from Huawei is the same walk. |
| Demo data stored separately and always labelled | Mock values can never masquerade as the user's records. |
| Insights need magnitude + coverage thresholds, carry evidence and confidence | "13 more steps than usual" never reaches the screen. |
| Relationship insights always carry a causation caveat | Correlation ≠ causation, stated every time. |
| LLM receives a ~20-line aggregate profile + tool results only | No name, no raw samples; deeper history only via tools on demand. |
| Model requests widget *types*; app renders trusted native components from deterministic data | The model never generates UI or numbers shown in charts. |
| Urgent-symptom screen runs before any engine | Safety answer doesn't depend on the model. |
| Swift 5 language mode in the app target, Swift 6 in BlithCore | App code is compiled only in CI; this keeps HealthKit/SwiftUI concurrency friction low while the logic package stays strict. |
| iOS 18 minimum, Liquid Glass on iOS 26 with material fallbacks | `Tab` API + Observation; native glass tab bar, composer, picker and buttons. |

## Future-proofing (not built)

- `HealthEvent` (date, kind, title, note, bodyRegion, severity, relatedMetrics) is persisted in
  `HealthHistory.events` so a future body view and injury timeline ("twisted right ankle") can
  attach to history without a migration. There is no body UI or mascot in this phase.
- Background delivery (HKObserverQuery) can call `AppModel.refresh()`; the sync engine is
  already incremental and idempotent.
