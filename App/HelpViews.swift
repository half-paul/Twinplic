import AppKit
import SwiftUI

extension OpenWindowAction {
    /// The app may be menu bar only at this point, and a window needs it to be a regular app.
    @MainActor
    func showHelp(_ topic: HelpTopic?, model: AppModel) {
        if let topic { model.helpTopic = topic }
        NSApp.setActivationPolicy(.regular)
        self(id: CopyFXApp.helpWindowID)
        NSApp.activate()
    }
}

/// The question mark beside a control. Keep it outside any `.disabled` view, so help still
/// opens while a run has the controls locked.
struct HelpButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var isShowing = false

    let tip: HelpTip

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Help: \(tip.title)")
        .popover(isPresented: $isShowing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tip.title)
                    .font(.headline)
                Text(tip.message)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Learn More") {
                    isShowing = false
                    openWindow.showHelp(tip.topic, model: model)
                }
                .buttonStyle(.link)
            }
            .padding()
            .frame(width: 300, alignment: .leading)
        }
    }
}

/// For the Help menu and the menu bar icon, which have no window of their own to read
/// `openWindow` from.
struct HelpMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some View {
        Button("CopyFX Help") { openWindow.showHelp(nil, model: model) }
            .keyboardShortcut("?", modifiers: .command)
    }
}

struct HelpView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var topics: [HelpTopic] {
        let search = query.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return HelpTopic.allCases }
        return HelpTopic.allCases.filter { $0.searchText.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(topics, selection: $model.helpTopic) { topic in
                Label(topic.title, systemImage: topic.icon)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let topic = model.helpTopic {
                HelpPage(topic: topic)
                    .id(topic)
            } else {
                ContentUnavailableView("Choose a Topic", systemImage: "questionmark.circle")
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search Help")
        .onDisappear {
            // With the main window also closed, the app goes back to the menu bar only.
            let othersOpen = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && $0.title != CopyFXApp.helpWindowTitle }
            if !othersOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

private struct HelpPage: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(topic.title)
                    .font(.largeTitle.weight(.semibold))
                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if let heading = section.heading {
                            Text(heading).font(.title3.weight(.semibold))
                        }
                        ForEach(Array(lines(of: section).enumerated()), id: \.offset) { _, line in
                            HelpLine(text: line)
                        }
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func lines(of section: HelpSection) -> [String] {
        section.body.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

private struct HelpLine: View {
    private static let bullet = "• "

    let text: String

    var body: some View {
        if text.hasPrefix(Self.bullet) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                styled(String(text.dropFirst(Self.bullet.count)))
            }
            .padding(.leading, 6)
        } else {
            styled(text)
        }
    }

    private func styled(_ line: String) -> some View {
        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
            .fixedSize(horizontal: false, vertical: true)
    }
}
