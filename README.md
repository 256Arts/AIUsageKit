# AIUsageKit

Claude and Codex rate limits — how much of the five-hour window and the week is gone, and when
each refills — for any of 256 Arts' apps. Extracted from [App Sales](https://github.com/256Arts/App-Sales).

iOS, macOS, watchOS, and visionOS 26.

## What's in it

- **Sign-in** — Claude over OAuth (PKCE against Claude Code's public client, the code pasted back
  from Claude's page), Codex from a pasted or picked `~/.codex/auth.json`. Stored in the
  synchronizable Keychain so every device gets them.
- **Fetching** — `AIAssistants.shared` (`@Observable`): one fetch per assistant in flight, refreshes
  under an App Group `flock`, and the Mac refreshes 10 minutes early — a refresh token used twice
  gets its whole family revoked. `AIUsageCache` shares the last reading across the app, its widgets,
  and the menu bar extra.
- **Views** — `AIUsageSection` (a `List` section, its assistants side by side), `AIUsageBar` / `AIUsageColumn` / `AIUsageTrack`,
  `AIUsageOptions` (menu contents), `AIUsageSignInSheet`, `AIUsageSnippet`.
- **Widget** — `AIUsageWidget`, every home screen, Lock Screen, and watch face family.
- **Mac menu bar extra** — `AIUsageMenuBar` + `AIUsageMenuBarLabel`, with `DockIcon` and `LoginItem`.
- **App Intent** — `GetAIUsageIntent`, in the separate `AIUsageKitIntents` product.

## Adopting it

1. Add the package; link `AIUsageKit` to the app and each widget extension, and
   `AIUsageKitIntents` to the app alone.
2. Every one of those targets' Info.plist names the App Group and Keychain service:
   ```xml
   <key>AIUsageKit</key>
   <dict>
       <key>AppGroup</key>
       <string>group.com.example.app</string>
       <key>KeychainService</key>
       <string>com.example.app</string>
   </dict>
   ```
   The targets need that App Group and a shared Keychain access group; the Mac app needs
   `com.apple.security.files.user-selected.read-only` for the Codex file picker.
3. App Intents metadata: the app declares
   `struct AppIntents: AppIntentsPackage { static var includedPackages: [any AppIntentsPackage.Type] { [AIUsageKitIntentsPackage.self] } }`,
   each widget extension the same with `AIUsageKitPackage.self`.
4. Put `AIUsageSection()` in a list, `AIUsageWidget()` in the `WidgetBundle`, `GetAIUsageIntent()`
   in the `AppShortcutsProvider`, and present `AIUsageSignInSheet` for
   `AIAssistants.shared.signingIn` (and from wherever the app connects accounts).
5. While the app is in the foreground, call `AIAssistants.shared.refreshConnected()` once a minute
   so the widget follows along.
6. Mac: insert `MenuBarExtra { AIUsageMenuBar(mainWindowID:) } label: { AIUsageMenuBarLabel() }`
   (`.window` style) while `AIUsageDefaultsKey.menuBarExtra` is set in `AIUsageKit.defaults`; tell
   `DockIcon` when the main window opens and closes and when the extra is shown, and return
   `!DockIcon.keepsRunning` from `applicationShouldTerminateAfterLastWindowClosed`.

A `-screenshotMode` launch argument draws `AIUsage.examples` and stays off the Keychain.
