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
    /// Draws this limit in the week's place — its name for the title — rather than the window's own.
    var extra: AIUsageExtraLimit?

    var display: AIUsageDisplay
    /// Whether a tick shows where the bar is projected to stand when the window resets.
    var showsProjection = true
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

    public init(window: AIUsageWindow, usage: AIUsage, extra: AIUsageExtraLimit? = nil, display: AIUsageDisplay = .current, showsProjection: Bool = true, showsReset: Bool = true, showsMetric: Bool = false, titlesReset: Bool = false, trackHeight: CGFloat = 8, now: Date = .now) {
        self.window = window
        self.usage = usage
        self.extra = extra
        self.display = display
        self.showsProjection = showsProjection
        self.showsReset = showsReset
        self.showsMetric = showsMetric
        self.titlesReset = titlesReset
        self.trackHeight = trackHeight
        self.now = now
    }

    public var body: some View {
        if let limit = extra?.limit ?? display.relevant(usage)[window] {
            let title = extra?.name ?? window.title
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if titlesReset, let resetsAt = limit.resetsAt, resetsAt > now, let countdown = display.countdown(to: resetsAt, from: now) {
                        Text(countdown)
                            .monospacedDigit()
                    } else {
                        Text(title)
                    }

                    Spacer()

                    Text(showsMetric ? display.summary(of: limit) : display.percentage(of: limit))
                        .monospacedDigit()
                }

                AIUsageTrack(
                    fraction: display.fraction(of: limit),
                    tint: display.tint(for: limit, in: window),
                    height: trackHeight,
                    marker: showsProjection ? display.projectedFraction(of: limit, in: window, at: now) : nil)

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
                    // A used bar fills towards its far end, which is where the reset waits for it.
                    .multilineTextAlignment(display.metric == .used ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: display.metric == .used ? .trailing : .leading)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(accessibilityValue(of: limit)))
        }
    }
}

extension AIUsageBar {

    private func accessibilityValue(of limit: AIUsageLimit) -> String {
        let summary = display.summary(of: limit)
        guard showsProjection, let projected = limit.projectedUsed(in: window, at: now) else { return summary }

        let percent = projected.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(summary), projected \(percent) used by the reset", bundle: #bundle)
    }
}

/// The bar on its own: a faint track and a fill, and optionally a tick marking a projection.
///
/// Drawn rather than a `ProgressView`, because a tinted widget flattens a `ProgressView`'s track and
/// fill into one solid colour, so the bar reads as full whatever the figure. Here the track keeps its
/// transparency and only the fill is accented. The menu bar label draws the same bar under its text.
public struct AIUsageTrack: View {

    let fraction: Double
    var tint: Color
    var height: CGFloat
    /// Where to draw a tick, `0...1` along the track — `nil` for none.
    var marker: Double?

    public init(fraction: Double, tint: Color = .accentColor, height: CGFloat = 4, marker: Double? = nil) {
        self.fraction = fraction
        self.tint = tint
        self.height = height
        self.marker = marker
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
            .overlay {
                if let marker {
                    GeometryReader { proxy in
                        let width: CGFloat = 2
                        Capsule()
                            .fill(.primary)
                            .overlay(Capsule().stroke(.background, lineWidth: 0.5))
                            .frame(width: width, height: height)
                            .offset(x: min(max(proxy.size.width * min(max(marker, 0), 1) - width / 2, 0), proxy.size.width - width))
                            .frame(maxHeight: .infinity)
                    }
                    .clipShape(.capsule)
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
    /// Whether the assistant's further weekly limits get their own bars. Off where space is tight.
    var showsExtras: Bool

    public init(usage: AIUsage, display: AIUsageDisplay = .current, showsMetric: Bool = false, showsExtras: Bool = false) {
        self.usage = usage
        self.display = display
        self.showsMetric = showsMetric
        self.showsExtras = showsExtras
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
            if showsExtras {
                ForEach(usage.extras) { extra in
                    AIUsageBar(window: .week, usage: usage, extra: extra, display: display, showsMetric: showsMetric)
                }
            }

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
