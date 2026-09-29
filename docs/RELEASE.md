# Release & App Store checklist

Status: ✅ done in code · 🔧 needs an external step · ⚠️ known gap

| Area | Status | Notes |
|---|---|---|
| App icon 1024 (light + dark), no alpha | ✅ | `Assets.xcassets/AppIcon.appiconset`, sources in `design/` |
| Display name / bundle id | ✅ | Blith / `com.blith.health` (`ios/project.yml`) |
| iPhone only, portrait | ✅ | `TARGETED_DEVICE_FAMILY 1` |
| HealthKit entitlement | ✅ | `com.apple.developer.healthkit` (read-only; no clinical records) |
| HealthKit usage string | ✅ | `NSHealthShareUsageDescription` explains the purpose specifically |
| Permissions asked in context, minimum types | ✅ | Onboarding explains first; user picks categories; only used types requested |
| No dark patterns around HealthKit | ✅ | App never claims access was granted; "no data" states explain how to check access |
| App works without Health data | ✅ | Explicit, labelled sample-data mode (useful for App Review) |
| Health data not used for ads / not in iCloud | ✅ | Local only; no analytics SDKs |
| Third-party AI disclosure + consent (5.1.1, 5.1.2) | ✅ | Consent sheet before first AI request; off by default until chosen; revocable in Profile |
| Privacy manifest | ✅ | `PrivacyInfo.xcprivacy`: no tracking; health, fitness, user content (AI, unlinked); UserDefaults CA92.1 |
| Privacy policy URL | ✅/🔧 | `docs/PRIVACY.md` (linked in-app). Use the same URL in App Store Connect |
| Medical claims | ✅ | Pattern language only, causation caveats, "not a medical device" in Profile and sheets, urgent-symptom screen |
| Data deletion | ✅ | Profile › Delete all Blith data (no accounts exist) |
| Export compliance | ✅ | `ITSAppUsesNonExemptEncryption = NO` |
| Secrets not in repo | ✅ | OpenRouter key comes from gitignored `Secrets.xcconfig` or the Codemagic `blith_ai` group |
| Embedded API key | ⚠️ | The OpenRouter key ships inside the app binary. Before a wide release, move AI calls behind a small server proxy with per-install rate limits |
| App Store Connect app record | 🔧 | Create app `com.blith.health` in App Store Connect (API cannot create apps) |
| Bundle ID HealthKit capability | 🔧 | Enable HealthKit for `com.blith.health` in the developer portal |
| Codemagic signing | 🔧 | `ios-release` uses the team's App Store Connect integration named `codemagic1` |
| App Privacy answers | 🔧 | Health & Fitness + User Content: collected only when AI answers are on, not linked, not tracking, App Functionality |
| Screenshots | 🔧 | `ios-ci` produces simulator screenshots with sample data as a starting point |

## Shipping a TestFlight build

1. Create the App Store Connect app record for `com.blith.health` and enable HealthKit on the identifier.
2. In Codemagic, confirm the App Store Connect integration is named `codemagic1` (or edit `codemagic.yaml`).
3. Start the `ios-release` workflow for `main`.
