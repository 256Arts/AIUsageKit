import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// How much of one rate limit window is gone — or left — as a bar that warms as it fills.
///
/// Every surface that draws usage draws this: the home screen section, the widgets, the watch's
/// rectangular complication, and the Mac's menu bar extra. They differ only in whether there is room
/// for the reset line beneath it, which is what `showsReset` is for.
public struct AIUsageBar: View {

    let window: AIUsageWindow
    let usage: AIUsage

    var display: AIUsageDisplay
    /// The accessory families and the small widget have no room for a second line per bar.
    var showsReset = true
    /// Whether the figure says which way round it is — "39% left" rather than "39%" — where there is
    /// room, so a glance does not depend on remembering the setting.
    var showsMetric = false
    /// Whether the reset time stands in for the window's name — "2h 15m" rather than "5 Hours" —
    /// for the families with no room for both. The name stays while there is no time to show.
    var titlesReset = false
    /// Home screen bars are taller; accessory widgets keep a compact track.
    var trackHeight: CGFloat
    /// The moment the bar is shown, which for a widget's future timeline entry is not yet.
    var now: Date

    public init(window: AIUsageWindow, usage: AIUsage, display: AIUsageDisplay = .current, showsReset: Bool = true, showsMetric: Bool = false, titlesReset: Bool = false, trackHeight: CGFloat = 8, now: Date = .now) {
        self.window = window
        self.usage = usage
        self.display = display
        self.showsReset = showsReset
        self.showsMetric = showsMetric
        self.titlesReset = titlesReset
        self.trackHeight = trackHeight
        self.now = now
    }

    public var body: some View {
        if let limit = display.relevant(usage)[window] {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if titlesReset, let resetsAt = limit.resetsAt, resetsAt > now, let countdown = display.countdown(to: resetsAt, from: now) {
                        Text(countdown)
                            .monospacedDigit()
                    } else {
                        Text(window.title)
                    }

                    Spacer()

                    Text(showsMetric ? display.summary(of: limit) : display.percentage(of: limit))
                        .monospacedDigit()
                }

                AIUsageTrack(fraction: display.fraction(of: limit), tint: display.tint(for: limit, in: window), height: trackHeight)

                // The line is kept while there is no reset to show — a window nobody has started has
                // none — so the bars sit the same distance apart either way.
                if showsReset, display.timeStyle != .hidden {
                    Group {
                        if let resetsAt = limit.resetsAt, resetsAt > .now, let resetText = display.resetText(resetsAt) {
                            resetText
                        } else {
                            Text(verbatim: " ")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(window.title))
            .accessibilityValue(Text(display.summary(of: limit)))
        }
    }
}

/// The bar on its own: a faint track and a fill.
///
/// Drawn rather than a `ProgressView`, because a tinted widget flattens a `ProgressView`'s track and
/// fill into one solid colour, so the bar reads as full whatever the figure. Here the track keeps its
/// transparency and only the fill is accented. The menu bar label draws the same bar under its text.
public struct AIUsageTrack: View {

    let fraction: Double
    var tint: Color
    var height: CGFloat

    public init(fraction: Double, tint: Color = .accentColor, height: CGFloat = 4) {
        self.fraction = fraction
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        Capsule()
            .fill(.primary.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? height : 0))
                        #if canImport(WidgetKit)
                        .widgetAccentable()
                        #endif
                }
            }
            .frame(height: height)
    }
}

/// One assistant as a block: who it is and where both windows stand.
///
/// The shape the surfaces without a List use — the home screen widget, and the Mac's menu bar
/// extra — where the two bars need a heading of their own rather than a row around them.
public struct AIUsageColumn: View {

    let usage: AIUsage
    var display: AIUsageDisplay
    var showsMetric: Bool

    public init(usage: AIUsage, display: AIUsageDisplay = .current, showsMetric: Bool = false) {
        self.usage = usage
        self.display = display
        self.showsMetric = showsMetric
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: usage.assistant.systemImage)
                    .foregroundStyle(.secondary)

                Text(usage.assistant.name)
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            AIUsageBar(window: .fiveHour, usage: usage, display: display, showsMetric: showsMetric)
            AIUsageBar(window: .week, usage: usage, display: display, showsMetric: showsMetric)

            Spacer(minLength: 0)
        }
        .font(.caption2)
    }
}

/// The card Siri and Shortcuts show: the same block the home screen widget and the Mac's menu bar
/// extra draw, so the answer looks like the app rather than like a second rendering of it.
public struct AIUsageSnippet: View {

    let usage: AIUsage

    nonisolated public init(usage: AIUsage) {
        self.usage = usage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AIUsageColumn(usage: usage, display: .current)

            Text("Updated \(usage.fetched, format: .relative(presentation: .numeric))", bundle: #bundle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

#Preview {
    List {
        AIUsageBar(window: .fiveHour, usage: AIUsage.examples[0])
        AIUsageBar(window: .week, usage: AIUsage.examples[0])
    }
    .font(.footnote)
}

#Preview("Snippet") {
    AIUsageSnippet(usage: AIUsage.examples[0])
}
