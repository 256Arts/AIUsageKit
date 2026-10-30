import Foundation
import SwiftUI
import AppIntents

/// Where AIUsageKit keeps what it shares between an app, its extensions, and the reader's other
/// devices.
///
/// Read from an `AIUsageKit` dictionary in the Info.plist of every target that links the package —
/// the app and each widget extension — rather than set in code, because a widget timeline or an App
/// Intent can run before any of the host's own code has:
///
///     <key>AIUsageKit</key>
///     <dict>
///         <key>AppGroup</key>
///         <string>group.com.example.app</string>
///         <key>KeychainService</key>
///         <string>com.example.app</string>
///     </dict>
///
/// The App Group holds the shared cache, the display preferences, and the refresh lock; the
/// Keychain service, synchronizable, holds the sign-ins so they reach the reader's other devices.
public enum AIUsageKit {

    private static let configuration = Bundle.main.object(forInfoDictionaryKey: "AIUsageKit") as? [String: String] ?? [:]

    /// `nil` without one configured, which leaves every process to itself: nothing is cached for the
    /// others, and preferences fall back to their defaults.
    static let appGroupID = configuration["AppGroup"]

    static let keychainService = configuration["KeychainService"] ?? Bundle.main.bundleIdentifier ?? "AIUsageKit"

    /// The App Group's defaults, where the display preferences live — pass this as an `@AppStorage`
    /// store alongside the keys in `AIUsageDefaultsKey`.
    public static var defaults: UserDefaults? {
        appGroupID.flatMap(UserDefaults.init(suiteName:))
    }

    /// The App Group container, for the cache and the refresh lock.
    static var containerURL: URL? {
        appGroupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    /// A screenshot run — the `-screenshotMode` launch argument — draws `AIUsage.examples` and stays
    /// off the real Keychain.
    public static let isScreenshotRun = ProcessInfo.processInfo.arguments.contains("-screenshotMode")

    /// The AI usage widget's kind, for the app to reload it by once it has read something new.
    public static let widgetKind = "AIUsage"

    /// The host app's name, for the lines that send the reader back to it — taken from the enclosing
    /// `.app` even in an extension, whose own bundle is named something else.
    static let appName: String = {
        var url = Bundle.main.bundleURL
        while url.pathExtension != "app", url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        let bundle = url.pathExtension == "app" ? Bundle(url: url) ?? .main : .main
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ""
    }()
}

/// The display preferences in `AIUsageKit.defaults`.
public enum AIUsageDefaultsKey {
    public static let metric = "aiUsageMetric"
    public static let timeStyle = "aiUsageTimeStyle"
    public static let goal = "aiUsageGoal"
    public static let hidesUnreachable = "aiUsageHidesUnreachable"
    /// Whether the Mac's menu bar extra is shown — the host reads it to insert the `MenuBarExtra`.
    public static let menuBarExtra = "aiUsageMenuBarExtra"
    public static let menuBarStyle = "aiUsageMenuBarStyle"
    /// What the AI usage widget has learned about how often each assistant's figures move.
    static let widgetPacing = "aiUsageWidgetPacing"

    /// Every choice about how usage is drawn, for a screenshot run to reset.
    public static let displayOptions = [metric, timeStyle, goal, menuBarStyle, hidesUnreachable]
}

/// Makes this package's App Intents types — the assistant picker and the widget's configuration —
/// visible to a host's App Intents metadata. Include it in the host's own `AppIntentsPackage`.
public struct AIUsageKitPackage: AppIntentsPackage { }

extension Text {
    /// When the figures above were last read, as "Updated 8 minutes ago".
    ///
    /// Drawn from `.currentDate`, so it counts up on its own — in a widget between timeline entries
    /// as well as in the app — with nothing holding a clock for it.
    init(updated date: Date) {
        self.init("Updated \(Text(.currentDate, format: .reference(to: date, allowedFields: [.day, .hour, .minute], maxFieldCount: 1)))", bundle: #bundle)
    }
}

extension Data {
    /// Base64 without padding, and URL-safe, as PKCE requires.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
