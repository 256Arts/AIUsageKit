# AIUsageKit

Claude/Codex rate-limit reading, shared UI, widget, and menu bar extra for 256 Arts apps. README.md
has the feature rundown and adoption steps.

## Build

Swift package, no Xcode project. Products: `AIUsageKit`, `AIUsageKitIntents` (app-only, so
extensions don't register the intent twice). Platforms: iOS / macOS / watchOS / visionOS 26.
Swift language mode 5.

Verify: `swift test` (macOS), plus
`xcodebuild -scheme AIUsageKit-Package -destination generic/platform=<iOS|watchOS|visionOS> build`.

## Conventions

- Configuration comes from the host's Info.plist `AIUsageKit` dict (`AIUsageKit.swift`), never code:
  widget timelines and intents run before any host code.
- Every user-facing string takes `bundle: #bundle` (SwiftUI title inits use the `String(localized:)`
  overload); strings live in `Resources/Localizable.xcstrings`. Never name the host app in a string —
  interpolate `AIUsageKit.appName`. App Intents metadata strings (titles, `@Parameter`,
  `caseDisplayRepresentations`) resolve against the host's main bundle.
- `Views/AIUsageSection.swift` is `#if !os(watchOS)`; the menu bar file is macOS-only.
- Endpoints are undocumented CLI ones: parse every field defensively. Never let two refreshes of
  one sign-in overlap (see `AIAssistants`).
- Keychain key, file names, and defaults keys are persisted — renaming them signs readers out.
