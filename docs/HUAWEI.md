# Huawei Health integration

## Findings

- Huawei Health Kit ships an on-device SDK for Android/HarmonyOS only. **There is no iOS SDK.**
- From iOS, data is reachable only through the **Health Kit cloud REST API**, authorized with
  OAuth 2.0 (HUAWEI ID sign-in at `https://oauth-login.cloud.huawei.com/oauth2/v3/authorize`)
  and per-type scopes (steps, distance, calories, sleep, body weight, heart rate…).
- Requirements before any code can talk to it:
  1. A Huawei developer account and a project in AppGallery Connect.
  2. Health Kit enabled for the project and **scope approval by Huawei** (data-access review).
  3. OAuth client ID + secret. The authorization code must be exchanged for tokens on a
     **server** holding the secret (never in the app), which also refreshes tokens.
- Many users don't need this path: the Huawei Health iOS app can sync a Huawei watch's steps,
  sleep and heart rate into Apple Health, which Blith already reads via HealthKit.

## What exists in the code

- `HuaweiHealthProvider` (BlithCore) implements `HealthDataProvider`, maps Huawei data types
  (`com.huawei.continuous.steps.delta`, `…distance.delta`, `…calories.burnt`,
  `com.huawei.instantaneous.body_weight`, `…resting_heart_rate`, `…sleep.fragment`) and sleep
  states onto the normalized models with `ProviderKind.huawei` provenance, and builds the
  OAuth authorization URL. It reports `notConfigured` until given a `Configuration` and a
  `Transport`.
- `SourceMerger` prevents double counting when the same Huawei data arrives both through
  Apple Health and directly (max per hour/day, near-duplicate readings kept once).
- Tests cover the mapping and the merge (`HuaweiTests`).

## To activate

1. Complete the Huawei requirements above.
2. Implement `HuaweiHealthProvider.Transport` against the REST API (sampling-data statistics
   for daily totals; sample sets for weight and sleep fragments) with tokens from your server.
3. Add a "Connect Huawei Health" row in Profile › Connected data that opens
   `authorizationURL(state:)` in `ASWebAuthenticationSession`.
4. Run both providers through `SourceMerger.merge` in the sync engine.
