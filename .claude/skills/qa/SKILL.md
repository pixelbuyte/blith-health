---
name: qa
description: Practical engineering QA for the Blith iOS app — diff review, API verification against real declarations, BlithCore tests, XcodeGen and Codemagic ios-ci readiness, and critical-flow checks. Reports only actionable failures; never claims success without running the checks.
---

# /qa — Blith

There is no local Swift compiler for the app target. QA here means removing every reason `ios-ci` could fail
before it runs, then reading its result.

1. `git diff origin/main...HEAD --stat`, then read the full diff.
2. For every project symbol the diff uses (types, members, initializer labels, enum cases, router routes,
   `Palette`/`Typo` tokens), grep its declaration and confirm the exact spelling and signature.
3. SwiftUI: each `@ViewBuilder` branch returns a view; no `if` with mismatched result types outside builders;
   availability matches the deployment target in `ios/project.yml`.
4. Concurrency: no non-Sendable values crossing actors, no mutable statics, UI work on the main actor.
5. New or moved Swift files: they live under a globbed source path in `ios/project.yml` (CI runs
   `xcodegen generate`).
6. If `ios/BlithCore` changed and a Swift toolchain exists: `cd ios/BlithCore && swift test`.
7. Critical flows to reason through: first launch with and without an Apple Watch, sample data, empty Health,
   Today → Readiness → back, Ask consent.
8. Report: failures with file:line and the fix, then warnings. Say plainly which checks could not run here
   (the app build always needs Codemagic `ios-ci`).
