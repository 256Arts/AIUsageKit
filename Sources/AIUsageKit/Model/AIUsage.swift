import Foundation
import AppIntents

/// A coding assistant whose rate limits the app can show.
///
/// Both of these are billed by a subscription rather than per call, so the number that matters is
/// not a bill — it is how much of the current window is left before the assistant stops answering.
public enum AIAssistant: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .claude: String(localized: "Claude", bundle: #bundle)
        case .codex: String(localized: "Codex", bundle: #bundle)
        }
    }

    public var systemImage: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "seal"
        }
    }

    /// The terminal command that prints a sign-in to paste in — `nil` for an assistant the app can
    /// sign into itself.
    ///
    /// Claude has an OAuth sign-in the app can drive, which works the same on a phone as on a Mac
    /// and asks the terminal for nothing. Codex's tokens only come out of its own command, so its
    /// sign-in is a copy of the file the CLI keeps.
    public var signInCommand: String? {
        switch self {
        case .claude: nil
        case .codex: "cat ~/.codex/auth.json"
        }
    }

    /// The file the terminal keeps this assistant's sign-in in, under the home folder — `nil` for
    /// an assistant that does not keep one.
    ///
    /// Claude Code puts its sign-in in the login Keychain rather than on disk, in an item only it
    /// can open, so there is no file to offer and `signInCommand` is the whole story. Only the Mac's
    /// sign-in sheet reads this, and only to point the file picker somewhere useful: a sandboxed app
    /// cannot reach the path until the reader hands it the file.
    public var credentialsFile: String? {
        switch self {
        case .claude: nil
        case .codex: ".codex/auth.json"
        }
    }
}

extension AIAssistant: AppEnum {

    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Assistant" }

    /// Spelled out rather than built from `name`, because App Intents reads these at build time to
    /// compile the widget configuration's picker.
    public static var caseDisplayRepresentations: [AIAssistant: DisplayRepresentation] {
        [
            .claude: DisplayRepresentation(title: "Claude", image: .init(systemName: "asterisk")),
            .codex: DisplayRepresentation(title: "Codex", image: .init(systemName: "seal")),
        ]
    }
}

/// How much of one rate limit window has been spent, and when it empties again.
public struct AIUsageLimit: Codable, Hashable, Sendable {
    /// `0...1`, and past `1` only where an assistant reports going over.
    public let used: Double
    /// `nil` where the assistant does not say — a window nobody has entered yet has no reset time.
    public let resetsAt: Date?

    public init(used: Double, resetsAt: Date?) {
        self.used = used
        self.resetsAt = resetsAt
    }
}

/// A weekly limit that applies to one model or feature on top of the overall week — Claude's cap on
/// a single model, say. Metered over the same rolling week, so it is paced like one.
public struct AIUsageExtraLimit: Codable, Hashable, Identifiable, Sendable {
    /// Stable across readings, so a notification for it can be replaced rather than doubled.
    public let id: String
    /// What the limit covers, as the reader would say it — "Fable".
    public let name: String
    public let limit: AIUsageLimit

    public init(id: String, name: String, limit: AIUsageLimit) {
        self.id = id
        self.name = name
        self.limit = limit
    }
}

/// One assistant's limits right now.
///
/// Both assistants meter a rolling week, and may also meter a rolling five hours, so both land here
/// rather than in a per-assistant shape. Limits beyond those two are `extras`.
public struct AIUsage: Codable, Hashable, Identifiable, Sendable {
    public let assistant: AIAssistant
    /// The subscription the limits belong to, where the assistant names it.
    public let plan: String?
    public let fiveHour: AIUsageLimit?
    public let week: AIUsageLimit?
    /// Further weekly limits, such as one model's own cap. Empty where the assistant reports none.
    public let extras: [AIUsageExtraLimit]
    public let fetched: Date

    public var id: AIAssistant { assistant }

    public init(assistant: AIAssistant, plan: String?, fiveHour: AIUsageLimit?, week: AIUsageLimit?, extras: [AIUsageExtraLimit] = [], fetched: Date) {
        self.assistant = assistant
        self.plan = plan
        self.fiveHour = fiveHour
        self.week = week
        self.extras = extras
        self.fetched = fetched
    }

    /// Readings cached before `extras` existed have none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assistant = try container.decode(AIAssistant.self, forKey: .assistant)
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        fiveHour = try container.decodeIfPresent(AIUsageLimit.self, forKey: .fiveHour)
        week = try container.decodeIfPresent(AIUsageLimit.self, forKey: .week)
        extras = try container.decodeIfPresent([AIUsageExtraLimit].self, forKey: .extras) ?? []
        fetched = try container.decode(Date.self, forKey: .fetched)
    }
}

public enum AIUsageError: LocalizedError {
    case notSignedIn
    /// The saved sign-in was refused: expired, revoked, or signed out somewhere else.
    case signInExpired
    /// What was pasted or picked is not a sign-in this assistant issued.
    case unreadableSignIn(AIAssistant)
    case assistant(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            String(localized: "You are not connected to this assistant.", bundle: #bundle)
        case .signInExpired:
            String(localized: "The sign-in has expired. Sign in again in \(AIUsageKit.appName).", bundle: #bundle)
        case .unreadableSignIn(let assistant):
            String(localized: "That is not a \(assistant.name) sign-in.", bundle: #bundle)
        case .assistant(let message):
            message
        }
    }
}

extension AIUsage {

    /// How long ago the example figures were read.
    private static let exampleAge: TimeInterval = 8 * 60

    /// Plausible figures for previews and App Store screenshots.
    ///
    /// Reset times are offsets from `.now`, so the section reads the same whichever day a run
    /// happens on — including `fetched`, which is a few
    /// minutes back rather than this instant so the "Updated" line reads like a real one.
    public static let examples: [AIUsage] = [
        AIUsage(
            assistant: .claude,
            plan: "Max",
            fiveHour: AIUsageLimit(used: 0.34, resetsAt: .now.addingTimeInterval(2 * 60 * 60)),
            week: AIUsageLimit(used: 0.61, resetsAt: .now.addingTimeInterval(3 * 24 * 60 * 60)),
            extras: [AIUsageExtraLimit(id: "fable", name: "Fable", limit: AIUsageLimit(used: 0.22, resetsAt: .now.addingTimeInterval(3 * 24 * 60 * 60)))],
            fetched: .now.addingTimeInterval(-exampleAge)),
        AIUsage(
            assistant: .codex,
            plan: "Plus",
            fiveHour: AIUsageLimit(used: 0.08, resetsAt: .now.addingTimeInterval(4 * 60 * 60)),
            week: AIUsageLimit(used: 0.45, resetsAt: .now.addingTimeInterval(5 * 24 * 60 * 60)),
            fetched: .now.addingTimeInterval(-exampleAge)),
    ]
}

/// Lets an `AIUsageError` surface in Shortcuts and widgets with the same wording the app shows.
extension AIUsageError: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        "\(errorDescription ?? String(localized: "An unknown error occurred.", bundle: #bundle))"
    }
}
