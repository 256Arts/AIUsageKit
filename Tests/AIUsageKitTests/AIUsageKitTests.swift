import Foundation
import Testing
@testable import AIUsageKit

struct SignInReadingTests {

    /// A JWT whose payload is `claims`, unsigned — only the payload is ever read.
    private func jwt(_ claims: [String: Any]) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: claims).base64URLEncoded
        return "e30.\(payload).signature"
    }

    @Test func readsCodexAuthFile() throws {
        let token = try jwt(["exp": 2_000_000_000, "email": "dev@example.com", "https://api.openai.com/auth": ["chatgpt_account_id": "acct"]])
        let file = #"{"tokens": {"access_token": "\#(token)", "refresh_token": "refresh"}}"#

        let signIn = try #require(AIUsageSignIn.read(file, for: .codex))
        #expect(signIn.refreshToken == "refresh")
        #expect(signIn.accountID == "acct")
        #expect(signIn.label == "dev@example.com")
        #expect(signIn.expires == Date(timeIntervalSince1970: 2_000_000_000))
    }

    @Test func readsBareTokenWrappedAcrossLines() throws {
        let token = try jwt(["email": "dev@example.com"])
        let wrapped = String(token.prefix(10)) + "\n  " + String(token.dropFirst(10))

        #expect(AIUsageSignIn.read(wrapped, for: .codex)?.accessToken == token)
    }

    @Test func refusesPastesForClaude() {
        #expect(AIUsageSignIn.read("anything", for: .claude) == nil)
    }

    @Test func namesPlans() {
        #expect(AIUsageSignIn.planName("free_workspace") == "Free Workspace")
        #expect(AIUsageSignIn.planName("") == nil)
    }
}

struct DisplayTests {

    private let now = Date.now

    private func usage(fiveHour: Double, week: Double, fiveHourResetsIn: TimeInterval = 60 * 60, weekResetsIn: TimeInterval = 3 * 24 * 60 * 60) -> AIUsage {
        AIUsage(
            assistant: .claude,
            plan: nil,
            fiveHour: AIUsageLimit(used: fiveHour, resetsAt: now.addingTimeInterval(fiveHourResetsIn)),
            week: AIUsageLimit(used: week, resetsAt: now.addingTimeInterval(weekResetsIn)),
            fetched: now)
    }

    @Test func clampsOverfullWindows() {
        let display = AIUsageDisplay(metric: .remaining, timeStyle: .relative, goal: .none)
        #expect(display.fraction(of: AIUsageLimit(used: 1.2, resetsAt: nil)) == 0)
    }

    @Test func warnsLikeABatteryWithNoGoal() {
        let display = AIUsageDisplay.default
        #expect(display.warning(for: AIUsageLimit(used: 0.5, resetsAt: nil), in: .week) == nil)
        #expect(display.warning(for: AIUsageLimit(used: 0.8, resetsAt: nil), in: .week) == .orange)
        #expect(display.warning(for: AIUsageLimit(used: 0.95, resetsAt: nil), in: .week) == .red)
    }

    @Test func warnsWhenBehindPaceToUseAll() {
        let display = AIUsageDisplay(metric: .used, timeStyle: .relative, goal: .useAll)
        // Four of five hours gone, a fifth of the window used.
        let limit = AIUsageLimit(used: 0.2, resetsAt: now.addingTimeInterval(60 * 60))
        #expect(display.warning(for: limit, in: .fiveHour, at: now) == .orange)
    }

    @Test func tightestIsTheFiveHoursWhileTheWeekHasRoom() {
        #expect(usage(fiveHour: 0.1, week: 0.6).tightestWindow == .fiveHour)
    }

    @Test func tightestIsTheWeekOnceItHoldsLessThanTheFiveHours() {
        #expect(usage(fiveHour: 0.1, week: 0.99).tightestWindow == .week)
    }

    @Test func headlinesTheFiveHoursOverAFullerWeekWithMoreLeft() {
        let claude = usage(fiveHour: 0.2, week: 0.1)
        let codex = AIUsage(assistant: .codex, plan: nil, fiveHour: nil, week: AIUsageLimit(used: 0.5, resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60)), fetched: now)
        #expect([codex, claude].closestToRunningOut?.assistant == .claude)
    }

    @Test func exhaustedUntilTheLaterReset() {
        let exhausted = usage(fiveHour: 1, week: 1)
        #expect(exhausted.exhaustedUntil(at: now) == now.addingTimeInterval(3 * 24 * 60 * 60))
        #expect(usage(fiveHour: 0.5, week: 0.5).exhaustedUntil(at: now) == nil)
    }

    @Test func hidesAWeekThatCannotRunOut() {
        let display = AIUsageDisplay(metric: .used, timeStyle: .relative, goal: .none, hidesUnreachable: true)
        // An hour to the reset, 90% of the week left: no amount of work spends it.
        let relevant = display.relevant(usage(fiveHour: 0.2, week: 0.1, weekResetsIn: 60 * 60))
        #expect(relevant.week == nil)
        #expect(relevant.fiveHour != nil)
    }
}
