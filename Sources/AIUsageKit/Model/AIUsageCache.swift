import Foundation

/// The last figures read for each assistant, in the App Group beside the sales cache.
///
/// A usage fetch is not as cheap as it looks. Both assistants hand out refresh tokens that rotate,
/// and a token used twice gets its whole family revoked — which would sign the reader's own terminal
/// out, not just the app. `AIAssistants` keeps one fetch per assistant in flight, but only within
/// a process, and there are three more processes that want the same numbers: the widget extension,
/// the watch's, and the Mac's menu bar extra. This is what stops each of them being that process at
/// the same moment, and it is also what lets a widget draw something the instant it is placed.
public enum AIUsageCache {

    /// How long a reading is worth showing before someone should go and ask again.
    ///
    /// Tuned to the shorter of the two windows: a five-hour limit moves by about 5% in fifteen
    /// minutes of steady work, which is under the rounding on every figure the app draws.
    public static let freshness: TimeInterval = 15 * 60

    /// How old a reading can be before the once-a-minute refresh asks again: every second minute,
    /// less a little so a slow fetch does not push it to the third.
    ///
    /// The assistants answer `429` to about 4 in 10 requests made once a minute.
    public static let pollAge: TimeInterval = 110

    private static let fileName = "ai-usage-cache.json"

    private static var storageURL: URL? {
        AIUsageKit.containerURL?.appendingPathComponent(fileName)
    }

    /// Everything cached, however old — what a widget draws while its own fetch is still in flight.
    public static func all() -> [AIUsage] {
        // The menu bar extra reads nothing else, so this is where a screenshot run gets its figures.
        if AIUsageKit.isScreenshotRun { return AIUsage.examples }

        guard let storageURL, let data = try? Data(contentsOf: storageURL) else { return [] }

        return (try? JSONDecoder().decode([AIUsage].self, from: data)) ?? []
    }

    public static func usage(for assistant: AIAssistant) -> AIUsage? {
        all().first { $0.assistant == assistant }
    }

    /// The cached reading, or `nil` once it is older than `maxAge`.
    public static func usage(for assistant: AIAssistant, newerThan maxAge: TimeInterval) -> AIUsage? {
        guard let usage = usage(for: assistant), usage.fetched.timeIntervalSinceNow > -maxAge else { return nil }

        return usage
    }

    static func save(_ usage: AIUsage) {
        var cached = all()
        cached.removeAll { $0.assistant == usage.assistant }
        cached.append(usage)
        write(cached)
    }

    static func clear(_ assistant: AIAssistant) {
        write(all().filter { $0.assistant != assistant })
    }

    private static func write(_ usage: [AIUsage]) {
        guard let storageURL, let data = try? JSONEncoder().encode(usage) else { return }

        try? data.write(to: storageURL)
    }
}

/// Until when an assistant should be left alone, in the App Group since every process's requests
/// count against the same limit.
enum AIUsageCooldown {

    private static func key(for assistant: AIAssistant) -> String {
        "aiUsageCooldown.\(assistant.rawValue)"
    }

    static func isActive(for assistant: AIAssistant) -> Bool {
        guard let until = AIUsageKit.defaults?.object(forKey: key(for: assistant)) as? Date else { return false }

        return until > .now
    }

    static func start(for assistant: AIAssistant, lasting duration: TimeInterval) {
        AIUsageKit.defaults?.set(Date.now.addingTimeInterval(duration), forKey: key(for: assistant))
    }

    static func clear(_ assistant: AIAssistant) {
        AIUsageKit.defaults?.removeObject(forKey: key(for: assistant))
    }
}
