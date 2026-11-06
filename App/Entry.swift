import AppKit
import TwinplicCore
import CoreServices
import Foundation
import SwiftUI

/// One binary, two roles: the app, or a headless run started by launchd.
@main
enum Entry {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == LaunchAgentScheduler.runTaskArgument {
            runScheduled(taskID: arguments[2])
        }
        TwinplicApp.main()
    }

    @MainActor
    private static func runScheduled(taskID: String) -> Never {
        do {
            let store = TaskStore()
            guard let id = UUID(uuidString: taskID), let task = try store.loadTasks().first(where: { $0.id == id }) else {
                fputs("Twinplic: no task with id \(taskID)\n", stderr)
                exit(2)
            }
            ScheduledRunPanel.run(task, store: store)
        } catch {
            fputs("Twinplic: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

/// Closing the main window leaves the app running in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when macOS opened the app at login, so it starts in the menu bar with no window.
    @MainActor static var startsHidden = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        let launchKind = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        if event.eventID == AEEventID(kAEOpenApplication), launchKind == OSType(keyAELaunchedAsLogInItem) {
            Self.startsHidden = true
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct TwinplicApp: App {
    static let mainWindowID = "main"
    static let helpWindowID = "help"
    static let helpWindowTitle = "Twinplic Help"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Twinplic", id: Self.mainWindowID) {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Backup") { model.addTask() }
                    .keyboardShortcut("n")
            }
            CommandGroup(replacing: .help) {
                HelpMenuItem(model: model)
            }
        }

        Window(Self.helpWindowTitle, id: Self.helpWindowID) {
            HelpView()
                .environment(model)
                .frame(minWidth: 680, minHeight: 480)
        }

        MenuBarExtra(
            "Twinplic",
            systemImage: model.activeRuns.isEmpty ? "externaldrive.badge.timemachine" : "arrow.triangle.2.circlepath"
        ) {
            MenuBarContent()
                .environment(model)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var runningTasks: [BackupTask] {
        model.tasks.filter { model.activeRuns[$0.id] != nil }
    }

    var body: some View {
        ForEach(runningTasks) { task in
            Text("\(task.name): \(status(of: task))")
        }
        if !runningTasks.isEmpty {
            Divider()
        }
        Button("Open Twinplic") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: TwinplicApp.mainWindowID)
            NSApp.activate()
        }
        HelpMenuItem(model: model)
        Toggle("Launch at Login", isOn: launchAtLogin)
        Divider()
        Button("Quit Twinplic") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { model.launchesAtLogin },
            set: { model.setLaunchesAtLogin($0) }
        )
    }

    private func status(of task: BackupTask) -> String {
        let run = model.activeRuns[task.id]
        if run?.isPaused == true { return "Paused" }
        guard let progress = run?.progress, progress.phase != .scanning else {
            return ["Scanning…", run?.timeLeft].compactMap(\.self).joined(separator: " · ")
        }
        let percent = progress.fraction.formatted(.percent.precision(.fractionLength(0)))
        return [percent, run?.timeLeft].compactMap(\.self).joined(separator: " · ")
    }
}
