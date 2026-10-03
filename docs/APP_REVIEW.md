# App Store Connect: review notes and metadata

Paste these into App Store Connect. Fill each `[bracket]` first. They match the app as of build 4.

## App Review Information › Notes

```
Blith has no accounts, no login and no in-app purchases. No credentials or sample files are needed.

To review without personal health data: on the connect screen in onboarding, tap "Explore with sample data". A built-in sample person fills every screen, and the app labels it as sample data. To use real data, tap "Connect Apple Health". Blith only reads Apple Health and never writes to it.

Main features: Today (Readiness, Sleep and Load scores against the person's own usual range, plus overnight readings), Activity, Sleep, Body (a 3D body map where people keep private, dated notes) and Ask (an assistant for questions about the person's own data).

Ask: the first question opens a consent screen. "Allow AI answers" sends the question and the readings needed to answer it through OpenRouter (openrouter.ai) to an AI model. "Keep answers on this iPhone" answers on the device. This can be changed at any time in Profile › AI assistant.

Delete data: Profile (the avatar on Today) › Delete all Blith data.

External services: Apple HealthKit (on device, read only) and OpenRouter (only after consent). No analytics, advertising, login, payment or backend services.

Blith works the same in every region. Units default to the device region and can be changed in onboarding or Profile.

Blith is a wellness app, not a medical device, and it does not diagnose. The 3D anatomy model is built from BodyParts3D (CC BY-SA 2.1 JP) and Z-Anatomy (CC BY-SA 4.0), credited in the app on the Body screen.

A screen recording on a physical iPhone is attached to our reply in App Review.
```

Sign-in required: **No**. Contact: [name, phone, email].

## App Information

| Field | Value |
|---|---|
| Name | Blith |
| Subtitle (30) | Health, against your own normal |
| Primary category | Health & Fitness |
| Secondary category | Lifestyle (optional) |
| Privacy Policy URL | https://github.com/pixelbuyte1/blith-health/blob/main/docs/PRIVACY.md |
| Support URL | [a page or email link you control, for example a GitHub issues page or your site] |
| Age rating | Medical/Treatment Information: None. Everything else: None. Result: 4+ |
| Copyright | 2026 [your name or company] |

## Version 1.0 › Description

```
Blith turns your Apple Health history into a clear daily read, measured against your own usual range instead of someone else's.

Every morning you see three scores:
- Readiness: how recovered you look, from overnight heart rate variability, resting heart rate and sleep.
- Sleep: how well last night went, with stages, timing and consistency.
- Load: how much the day asked of your body.

Each reading is compared with the middle half of your own last 60 days, so "usual" means usual for you.

Also in Blith:
- Overnight readings: heart rate, HRV, breathing rate, blood oxygen and wrist temperature, each shown against your own range.
- Activity and walking trends by week and month.
- Body: a 3D body map where you keep private, dated notes, like a sore knee or a rolled ankle.
- Ask: questions about your own data, answered in plain words. Answers stay on your iPhone unless you choose cloud answers.

Private by design: no account, no ads, no tracking. Your data stays on your iPhone. Blith only reads Apple Health.

Blith is not a medical device and does not diagnose or treat any condition.
```

Keywords (100): `readiness,recovery,hrv,sleep score,resting heart rate,apple health,baseline,trends,wellness,body`

Promotional text: `Daily scores measured against your own usual range, from the Apple Health data you already have.`

## App Privacy (data collection answers)

Data is collected only when the person turns on AI answers in Ask. Answer:

- **Health** (Health): collected, *not linked* to identity, *not used for tracking*, purpose **App Functionality**.
- **Fitness** (Fitness): same as Health.
- **Other User Content** (questions and body notes sent to the assistant): same as Health.
- Everything else: not collected.

This matches `ios/Blith/Resources/PrivacyInfo.xcprivacy`.

## Screen recording (required by Guideline 2.1)

Record on a physical iPhone on the latest iOS. Start before tapping the icon. Show: launch, onboarding, Explore with
sample data and the Apple Health permission sheet, Today, a score detail, Activity, Sleep, Body (add a note), Ask
(consent screen, then an answer), Profile › Delete all Blith data.
