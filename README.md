# Don’t Smoke

A calm, native SwiftUI quit-smoking companion with SwiftData persistence.

## Links

- [Support](https://appi-dev.github.io/dont-smoke-ios/support.html)
- [Privacy Policy](https://appi-dev.github.io/dont-smoke-ios/privacy.html)

## Run

Open `DontSmoke.xcodeproj` in Xcode and run the `DontSmoke` scheme on an iPhone simulator running iOS 17 or later.

Onboarding data is staged in memory and committed to SwiftData at completion. The app includes a live Today dashboard, craving-rescue breathing exercise, Progress and Me tabs, optional My Why photos, and profile-backed currency selection.

## Validation

The app and calculation-test target have compiled successfully. Simulator test execution has stalled during previous verification attempts; a successful build is not a passing test run. The existing XCTest suite covers duration, cigarettes avoided, money saved, and future quit dates.

## Milestone workflow

Keep changes incremental and create a focused commit for each completed milestone. Preserve existing features and tests, record validation results, and exclude build products and local Xcode user settings from commits.
