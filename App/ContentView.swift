import AppKit
import CopyFXCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var taskToDelete: BackupTask?

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.tasks) { task in
                    TaskRow(task: task)
                        .tag(task.id)
                        .contextMenu {
                            Button("Delete…", role: .destructive) { taskToDelete = task }
                                .disabled(model.isBusy(task.id))
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button { model.addTask() } label: {
                        Label("New Backup", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let id = model.selection, let task = model.binding(for: id) {
                TaskDetailView(task: task)
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No Backup Selected", systemImage: "externaldrive.badge.timemachine")
                } description: {
                    Text("Create a backup to copy a folder or disk to another location.")
                } actions: {
                    Button("New Backup") { model.addTask() }
                }
            }
        }
        .onAppear {
            model.refreshLaunchAtLogin()
            if AppDelegate.startsHidden {
                AppDelegate.startsHidden = false
                // SwiftUI opens the window itself, so close it once that has finished.
                DispatchQueue.main.async {
                    NSApp.windows.first { $0.canBecomeMain }?.close()
                }
                return
            }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            model.reloadHistories()
        }
        // With the window closed, the menu bar icon is the app's only presence.
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLaunchAtLogin()
            model.refreshFullDiskAccess()
            model.reloadHistories()
        }
        .alert(item: $model.alert) { alert in
            guard alert.offersAccessSettings else {
                return Alert(title: Text(alert.title), message: Text(alert.message))
            }
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text("Open System Settings")) { model.openFullDiskAccessSettings() },
                secondaryButton: .cancel(Text("Not Now"))
            )
        }
        .sheet(item: $model.preview) { PreviewSheet(result: $0) }
        .confirmationDialog(
            "This destination has files CopyFX didn't put there",
            isPresented: consentBinding,
            titleVisibility: .visible,
            presenting: model.pendingConsent
        ) { task in
            Button("Preview Changes") {
                model.pendingConsent = nil
                model.makePreview(task)
            }
            Button("Back Up Anyway", role: .destructive) { model.confirmPendingRun() }
            Button("Cancel", role: .cancel) { model.pendingConsent = nil }
        } message: { task in
            Text(consentMessage(for: task))
        }
        .confirmationDialog(
            "Delete “\(taskToDelete?.name ?? "")”?",
            isPresented: deleteBinding,
            titleVisibility: .visible,
            presenting: taskToDelete
        ) { task in
            Button("Delete Backup Task", role: .destructive) { model.delete(task) }
        } message: { _ in
            Text("This removes the task, its schedule and its history. Files already backed up stay on the destination.")
        }
    }

    private func consentMessage(for task: BackupTask) -> String {
        let outcome = task.safetyNetEnabled
            ? "Files that don't match the source will move to the \(Reserved.safetyNetFolder) folder and be deleted after \(task.safetyNetRetentionDays) days."
            : "SafetyNet is off, so files that don't match the source will be permanently deleted."
        return "\(task.destinationPath)\n\n\(outcome)"
    }

    private var consentBinding: Binding<Bool> {
        Binding(
            get: { model.pendingConsent != nil },
            set: { if !$0 { model.pendingConsent = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { taskToDelete != nil },
            set: { if !$0 { taskToDelete = nil } }
        )
    }
}

private struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: BackupTask

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.name.isEmpty ? "Untitled" : task.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var lastRun: RunRecord? { model.histories[task.id]?.first }

    private var subtitle: String {
        if let run = model.activeRuns[task.id] {
            if run.isPaused { return "Paused" }
            guard let progress = run.progress, progress.phase != .scanning else {
                return ["Scanning…", run.timeLeft].compactMap(\.self).joined(separator: " · ")
            }
            let percent = progress.fraction.formatted(.percent.precision(.fractionLength(0)))
            return [task.dryRun ? "Dry run" : "Running", percent, run.timeLeft].compactMap(\.self).joined(separator: " · ")
        }
        guard let lastRun else { return "Never run" }
        let when = lastRun.finishedAt.formatted(.relative(presentation: .named))
        return lastRun.wasDryRun ? "Dry run · \(when)" : when
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let run = model.activeRuns[task.id] {
            if run.isPaused {
                Image(systemName: "pause.circle").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        } else if let lastRun {
            lastRun.icon
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}

extension RunRecord {
    var wasDryRun: Bool { isDryRun == true }

    /// A dry run must never read as a finished backup.
    var title: String {
        wasDryRun ? "Dry run: \(status.title)" : status.title
    }

    @ViewBuilder
    var icon: some View {
        if wasDryRun, status == .success {
            Image(systemName: "eye.circle.fill").foregroundStyle(.secondary)
        } else {
            status.icon
        }
    }
}

extension RunRecord.Status {
    var title: String {
        switch self {
        case .success: "Completed"
        case .completedWithErrors: "Completed with errors"
        case .cancelled: "Stopped"
        case .failed: "Didn't run"
        case .skipped: "Skipped"
        }
    }

    @ViewBuilder
    var icon: some View {
        switch self {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .completedWithErrors:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "forward.circle.fill").foregroundStyle(.secondary)
        }
    }
}
