#if !os(watchOS)
import SwiftUI
import UniformTypeIdentifiers
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The home screen's AI usage: how much of each connected assistant's five-hour and weekly limits
/// is gone, and when they refill, side by side.
///
/// A `Section`, for a `List` or `Form`. Presenting `AIUsageSignInSheet` for
/// `AIAssistants.shared.signingIn` is the host's, since a row's "Sign In Again" sets it.
public struct AIUsageSection: View {

    /// Bump to fetch usage afresh, from the screen's pull to refresh.
    var refreshCount: Int
    /// What to say while no assistant is connected — where in the host to sign in, say.
    var placeholder: Text?

    public init(refreshCount: Int = 0, placeholder: Text? = nil) {
        self.refreshCount = refreshCount
        self.placeholder = placeholder
    }

    @State private var assistants = AIAssistants.shared

    @AppStorage(AIUsageDefaultsKey.metric, store: AIUsageKit.defaults) private var metric: AIUsageMetric = .used
    @AppStorage(AIUsageDefaultsKey.timeStyle, store: AIUsageKit.defaults) private var timeStyle: AIUsageTimeStyle = .relative
    @AppStorage(AIUsageDefaultsKey.goal, store: AIUsageKit.defaults) private var goal: AIUsageGoal = .none
    @AppStorage(AIUsageDefaultsKey.hidesUnreachable, store: AIUsageKit.defaults) private var hidesUnreachable = false

    private var display: AIUsageDisplay {
        AIUsageDisplay(metric: metric, timeStyle: timeStyle, goal: goal, hidesUnreachable: hidesUnreachable)
    }
    private var connected: [AIAssistant] {
        AIUsageKit.isScreenshotRun ? AIUsage.examples.map(\.assistant) : assistants.connected
    }
    /// Kept by `AIAssistants` rather than here, so the app's once-a-minute refresh reaches the rows
    /// even while this section is scrolled out of the list and has no task of its own running.
    private var usage: [AIAssistant: AIUsage] {
        AIUsageKit.isScreenshotRun
            ? Dictionary(uniqueKeysWithValues: AIUsage.examples.map { ($0.assistant, $0) })
            : assistants.latest
    }

    public var body: some View {
        Section {
            if connected.isEmpty {
                (placeholder ?? Text("Sign in to Claude or Codex to see how much of each one's limits you have left.", bundle: #bundle))
                    .foregroundStyle(.secondary)
            } else {
                // Side by side, scrolling sideways once there isn't room for them all.
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Self.columnSpacing) {
                        ForEach(connected) { assistant in
                            AIUsageRow(assistant: assistant, usage: usage[assistant], error: assistants.failures[assistant]?.localizedDescription, needsSignIn: assistants.needsSignIn(assistant), display: display)
                                // An equal share of the row, but never narrower than the bars read at.
                                .containerRelativeFrame(.horizontal) { length, _ in
                                    let spacing = Self.columnSpacing * CGFloat(connected.count - 1)
                                    return max(Self.minimumColumnWidth, (length - spacing) / CGFloat(connected.count))
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        } header: {
            HStack {
                Label(String(localized: "AI Usage", bundle: #bundle), systemImage: "gauge.with.dots.needle.33percent")

                Spacer()

                Menu {
                    AIUsageOptions()
                } label: {
                    Label(String(localized: "Options", bundle: #bundle), systemImage: "switch.2")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
            }
        } footer: {
            if !connected.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    // The oldest of the readings above: with one assistant's fetch failed and its
                    // cached figures standing in, that is the one worth knowing the age of. A
                    // reading is shared with the widgets and the menu bar through the App Group, so
                    // this is often older than the moment the screen was opened — which is the
                    // point of showing it.
                    if let read = usage.values.map(\.fetched).min() {
                        Text(updated: read)
                    }

                    ForEach(display.warningReasons(for: usage.values), id: \.self) { reason in
                        Text(reason)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: connected) {
            await load()
        }
        .onChange(of: refreshCount) {
            Task { await load(maxAge: 0) }
        }
    }

    private static let columnSpacing: CGFloat = 20
    private static let minimumColumnWidth: CGFloat = 180

    /// On appearing, and for a newly connected assistant; the minute-by-minute refresh is the app's.
    private func load(maxAge: TimeInterval = AIUsageCache.freshness) async {
        guard !AIUsageKit.isScreenshotRun else { return }

        await assistants.refreshConnected(maxAge: maxAge)
    }
}

/// One assistant's two windows, or why they could not be read.
private struct AIUsageRow: View {

    let assistant: AIAssistant
    let usage: AIUsage?
    let error: String?
    let needsSignIn: Bool
    let display: AIUsageDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(assistant.name, systemImage: assistant.systemImage)

            if let usage {
                AIUsageBar(window: .fiveHour, usage: usage, display: display)
                AIUsageBar(window: .week, usage: usage, display: display)
            }

            // Shown under the last figures read, which have stopped moving until this is done.
            if needsSignIn {
                HStack {
                    Text("Your sign-in has expired.", bundle: #bundle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(String(localized: "Sign In Again", bundle: #bundle)) {
                        AIAssistants.shared.signingIn = assistant
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if usage != nil {
                EmptyView()
            } else if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The choices every surface that draws usage obeys, as menu contents — so the home screen section
/// and the Mac's menu bar extra offer exactly the same ones rather than drifting apart.
///
/// The metric and the time style live in the App Group, which is how the widgets and the watch
/// complications see them; changing either reloads the timelines, because a widget process will not
/// notice a preference it is not watching.
public struct AIUsageOptions<StyleItems: View, MenuBarItems: View>: View {

    /// Choices only the menu bar extra itself offers, among the ones about how usage is drawn.
    let styleItems: StyleItems
    /// Choices only the menu bar extra itself offers, beside the toggle that shows it.
    let menuBarItems: MenuBarItems

    @AppStorage(AIUsageDefaultsKey.metric, store: AIUsageKit.defaults) private var metric: AIUsageMetric = .used
    @AppStorage(AIUsageDefaultsKey.timeStyle, store: AIUsageKit.defaults) private var timeStyle: AIUsageTimeStyle = .relative
    @AppStorage(AIUsageDefaultsKey.goal, store: AIUsageKit.defaults) private var goal: AIUsageGoal = .none
    @AppStorage(AIUsageDefaultsKey.hidesUnreachable, store: AIUsageKit.defaults) private var hidesUnreachable = false
    #if os(macOS)
    @AppStorage(AIUsageDefaultsKey.menuBarExtra, store: AIUsageKit.defaults) private var showsMenuBarExtra = false
    #endif

    public init(@ViewBuilder styleItems: () -> StyleItems, @ViewBuilder menuBarItems: () -> MenuBarItems) {
        self.styleItems = styleItems()
        self.menuBarItems = menuBarItems()
    }

    public var body: some View {
        // Bindings rather than `.onChange`: these are menu contents, so a modifier on a wrapper
        // would be applied to every child and fire the reload once per picker.
        Section {
            Picker(String(localized: "Show", bundle: #bundle), selection: binding($metric)) {
                ForEach(AIUsageMetric.allCases) { metric in
                    Text(metric.name)
                        .tag(metric)
                }
            }
            // Submenus, as a Mac draws them anyway: laid inline, iOS drops the picker's name and
            // leaves "Used" and "Left" with nothing to say what they choose.
            .pickerStyle(.menu)

            Picker(String(localized: "Reset Time Style", bundle: #bundle), selection: binding($timeStyle)) {
                ForEach(AIUsageTimeStyle.allCases) { style in
                    Text(style.name)
                        .tag(style)
                }
            }
            .pickerStyle(.menu)

            styleItems

            Picker(String(localized: "Goal", bundle: #bundle), selection: binding($goal)) {
                ForEach(AIUsageGoal.allCases) { goal in
                    Text(goal.name)
                        .tag(goal)
                }
            }
            .pickerStyle(.menu)

            Toggle(String(localized: "Hide Irrelevant Limits", bundle: #bundle), isOn: binding($hidesUnreachable))
        }

        #if os(macOS)
        Section {
            Toggle(String(localized: "Show in Menu Bar", bundle: #bundle), isOn: $showsMenuBarExtra)

            menuBarItems
        }
        #endif
    }

    /// Writes the choice through, then tells the widgets — a widget process is not watching these
    /// defaults, so it has no other way to hear about the change.
    private func binding<Value>(_ source: Binding<Value>) -> Binding<Value> {
        Binding {
            source.wrappedValue
        } set: { newValue in
            source.wrappedValue = newValue
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }
}

extension AIUsageOptions where StyleItems == EmptyView, MenuBarItems == EmptyView {
    public init() {
        self.init { EmptyView() } menuBarItems: { EmptyView() }
    }
}

/// Connecting an assistant: sign in to it in a browser, or — where it has no sign-in an app can
/// drive — paste what its command line tool prints, or on a Mac hand over the file it keeps.
/// Presented by the host, wherever it lists the reader's accounts.
public struct AIUsageSignInSheet: View {

    let assistant: AIAssistant

    public init(assistant: AIAssistant) {
        self.assistant = assistant
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var text = ""
    @State private var error: String?
    @State private var choosingFile = false
    @State private var connecting = false
    /// The sign-in the reader is part way through, holding the secrets that finish it. Non-`nil`
    /// once the browser has been opened, which is also what brings the code field out.
    @State private var signInRequest: AIUsageAPI.SignInRequest?

    public var body: some View {
        NavigationStack {
            Form {
                if let signInCommand = assistant.signInCommand {
                    Section {
                        TextField(String(localized: "Sign-in", bundle: #bundle), text: $text, axis: .vertical)
                            .lineLimit(3...8)
                            .font(.footnote.monospaced())
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    } header: {
                        Text("Paste Sign-In", bundle: #bundle)
                    } footer: {
                        Text("Run `\(signInCommand)` in a terminal and paste what it prints.", bundle: #bundle)
                    }

                    #if os(macOS)
                    // Only for an assistant that keeps its sign-in in a file. Claude Code keeps its
                    // own in a Keychain item nothing else can open, and signs in here anyway.
                    if let credentialsFile = assistant.credentialsFile {
                        Section {
                            Button(String(localized: "Choose Sign-In File…", bundle: #bundle), systemImage: "folder") {
                                choosingFile = true
                            }
                        } footer: {
                            Text("Reads the sign-in your terminal is already using, at ~/\(credentialsFile). \(AIUsageKit.appName) keeps its own copy and never writes to the file.", bundle: #bundle)
                        }
                    }
                    #endif
                } else {
                    Section {
                        Button(String(localized: "Sign In with \(assistant.name)", bundle: #bundle), systemImage: "person.badge.key") {
                            let request = AIUsageAPI.claudeSignInRequest()
                            withAnimation {
                                signInRequest = request
                            }
                            openURL(request.url)
                        }
                    } footer: {
                        Text("Opens \(assistant.name) in your browser. \(AIUsageKit.appName) asks only to read your limits — the sign-in is its own, and leaves the one your terminal uses alone.", bundle: #bundle)
                    }

                    if signInRequest != nil {
                        Section {
                            TextField(String(localized: "Code", bundle: #bundle), text: code)
                                .font(.footnote.monospaced())
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                        } header: {
                            Text("Paste Code", bundle: #bundle)
                        } footer: {
                            Text("\(assistant.name) shows a code once you approve. Copy it and paste it here.", bundle: #bundle)
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Sign In to \(assistant.name)", bundle: #bundle))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: #bundle), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sign In", bundle: #bundle)) {
                        Task { await connect() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting)
                }
            }
            #if os(macOS)
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    read(contentsOf: url)
                case .failure(let failure):
                    error = failure.localizedDescription
                }
            }
            .fileDialogDefaultDirectory(defaultDirectory)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    /// A code copied off a web page brings a line break with it as often as not, and no code
    /// contains whitespace — so take it out as it arrives rather than leaving it to be hunted for.
    private var code: Binding<String> {
        Binding {
            text
        } set: { newValue in
            text = newValue.filter { !$0.isWhitespace }
        }
    }

    /// The folder the sign-in lives in, so the picker opens on it rather than somewhere a name
    /// beginning with a dot is hidden.
    ///
    /// A sandboxed app's own idea of the home folder is its container, so the real one has to come
    /// from the account record. Only the picker's starting point depends on this — nothing is read
    /// until the reader chooses a file.
    private var defaultDirectory: URL? {
        guard let credentialsFile = assistant.credentialsFile,
              let home = getpwuid(getuid())?.pointee.pw_dir, let path = String(validatingCString: home) else { return nil }

        let directory = URL(filePath: path)
            .appending(path: credentialsFile)
            .deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) ? directory : nil
    }

    #if os(macOS)
    /// Fills the field with the file the reader picked, so connecting is the same one step it is
    /// for a paste — and so what was read is on screen if it turns out not to be a sign-in.
    private func read(contentsOf url: URL) {
        // A file the reader picked is only readable while its security scope is held open.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            error = AIUsageError.unreadableSignIn(assistant).localizedDescription
            return
        }
        text = contents
    }
    #endif

    private func connect() async {
        error = nil
        connecting = true
        defer { connecting = false }

        do {
            if let signInRequest {
                AIAssistants.shared.connect(try await AIUsageAPI.claudeSignIn(code: text, request: signInRequest))
            } else {
                try AIAssistants.shared.connect(assistant, with: text)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    List {
        AIUsageSection()
    }
}
#endif
