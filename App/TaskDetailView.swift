import AppKit
import CopyFXCore
import SwiftUI

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Binding var task: BackupTask

    private var isBusy: Bool { model.isBusy(task.id) }
    private var isConfigured: Bool { !task.sourcePath.isEmpty && !task.destinationPath.isEmpty }
    private var lastRunID: UUID? { model.histories[task.id]?.first?.id }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $task.name)
                    .disabled(isBusy)
                HStack(spacing: 12) {
                    FolderCard(title: "Source", icon: "folder", path: $task.sourcePath, lastRunID: lastRunID)
                        .disabled(isBusy)
                        .overlay(alignment: .topTrailing) { HelpButton(tip: .source).padding(6) }
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    FolderCard(title: "Destination", icon: "externaldrive", path: $task.destinationPath, lastRunID: lastRunID)
                        .disabled(isBusy)
                        .overlay(alignment: .topTrailing) { HelpButton(tip: .destination).padding(6) }
                }
            }

            Section {
                RunStatusView(run: model.activeRuns[task.id], lastRun: model.histories[task.id]?.first)
                AccessBanner(problems: model.histories[task.id]?.first?.access)
                HStack {
                    Spacer()
                    Button("Preview") { model.makePreview(task) }
                        .disabled(isBusy || !isConfigured)
                    HelpButton(tip: .preview)
                    if let run = model.activeRuns[task.id] {
                        Button(run.isPaused ? "Continue" : "Pause") { model.togglePause(task.id) }
                        HelpButton(tip: .pause)
                        Button("Stop") { model.stop(task.id) }
                        HelpButton(tip: .stop)
                    } else {
                        Button(task.dryRun ? "Dry Run Now" : "Back Up Now") { model.start(task) }
                            .buttonStyle(.borderedProminent)
                            .disabled(isBusy || !isConfigured)
                        HelpButton(tip: task.dryRun ? .dryRunNow : .backUpNow)
                    }
                }
            }

            Group {
                Section("Options") {
                    HStack {
                        Picker("Mode", selection: $task.deleteExtras) {
                            Text("Mirror source").tag(true)
                            Text("Only add and update").tag(false)
                        }
                        .disabled(isBusy)
                        HelpButton(tip: .mode)
                    }
                    Text(task.deleteExtras
                        ? "The destination will match the source. Items removed from the source are removed here too."
                        : "Nothing is removed from the destination, so items you delete from the source stay in the backup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Toggle("SafetyNet", isOn: $task.safetyNetEnabled)
                            .disabled(isBusy)
                        HelpButton(tip: .safetyNet)
                    }
                    if task.safetyNetEnabled {
                        Stepper(value: $task.safetyNetRetentionDays, in: 1...365) {
                            Text("Keep replaced and removed items for \(task.safetyNetRetentionDays) days")
                        }
                        .disabled(isBusy)
                    } else {
                        Label("Replaced and removed items are deleted permanently.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Toggle("Verify each copied file", isOn: $task.verifyCopies)
                            .disabled(isBusy)
                        HelpButton(tip: .verify)
                    }

                    HStack {
                        Toggle("Dry run", isOn: $task.dryRun)
                            .disabled(isBusy)
                        HelpButton(tip: .dryRun)
                    }
                    if task.dryRun {
                        Label("Every run, including scheduled ones, only logs what would change. Nothing is backed up.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    ScheduleEditor(schedule: $task.schedule)
                        .disabled(isBusy)
                    if task.schedule != .manual {
                        HStack {
                            Toggle("Skip scheduled runs on battery power", isOn: $task.skipOnBattery)
                                .disabled(isBusy)
                            HelpButton(tip: .skipOnBattery)
                        }
                    }
                } header: {
                    header("Schedule", tip: .schedule)
                }

                Section {
                    TextEditor(text: excludesText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 90)
                        .disabled(isBusy)
                } header: {
                    header("Exclude", tip: .excludes)
                } footer: {
                    Text("One name or pattern per line, such as node_modules or *.tmp. Excluded items aren't copied, and aren't removed from the destination.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let history = model.histories[task.id], !history.isEmpty {
                Section {
                    ForEach(history) { HistoryRow(record: $0) }
                } header: {
                    header("History", tip: .history)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(task.name.isEmpty ? "Untitled" : task.name)
    }

    private func header(_ title: String, tip: HelpTip) -> some View {
        HStack(spacing: 4) {
            Text(title)
            HelpButton(tip: tip)
        }
    }

    private var excludesText: Binding<String> {
        Binding(
            get: { task.excludes.joined(separator: "\n") },
            set: { task.excludes = $0.components(separatedBy: "\n") }
        )
    }
}

private struct FolderCard: View {
    let title: String
    let icon: String
    @Binding var path: String
    /// A finished run changes the free space, so this refreshes it.
    let lastRunID: UUID?

    @State private var details = FolderDetails()

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(path.isEmpty ? "Choose…" : details.displayName ?? (path as NSString).lastPathComponent)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !path.isEmpty, let freeSpace = details.freeSpace {
                        Text(freeSpace)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Leaves room for the help button that sits over this corner.
                Spacer(minLength: 18)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(path.isEmpty ? "Choose a folder" : path)
        .task(id: FolderDetails.Key(path: path, lastRunID: lastRunID)) {
            let path = path
            details = await Task.detached { FolderDetails(path: path) }.value
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the \(title.lowercased()) folder or disk"
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path) }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

/// Asks the disk, which can be slow on a network volume, so this stays off the main thread.
private struct FolderDetails: Sendable {
    struct Key: Hashable {
        let path: String
        let lastRunID: UUID?
    }

    var displayName: String?
    var freeSpace: String?

    init() {}

    init(path: String) {
        guard !path.isEmpty else { return }
        displayName = FileManager.default.displayName(atPath: path)
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bytes = values?.volumeAvailableCapacityForImportantUsage {
            freeSpace = "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) free"
        }
    }
}

/// Always on screen, so the bar shows the live run or how the last one ended.
struct RunStatusView: View {
    let run: ActiveRun?
    let lastRun: RunRecord?
    /// Gives the current file a full line of its own.
    var stacked = false

    private var progress: RunProgress? { run?.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                if let pausedAt = run?.pausedAt, let resumesAt = run?.resumesAt {
                    Text("Continues in \(Text(timerInterval: pausedAt...resumesAt, countsDown: true))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if let progress, progress.phase != .scanning {
                    Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }

            if let run, !run.isPaused, progress == nil || progress?.phase == .scanning {
                // The total isn't known until scanning finishes.
                ProgressView().progressViewStyle(.linear)
            } else {
                ProgressView(value: progress?.fraction ?? idleFraction)
            }

            Group {
                if stacked {
                    detailText
                    rateText
                } else {
                    HStack {
                        detailText
                        Spacer()
                        rateText
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var detailText: some View {
        Text(detail)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var rateText: some View {
        Text(rate)
            .monospacedDigit()
    }

    private var title: String {
        if let run {
            return run.isPaused ? "Paused" : progress?.phase.rawValue ?? "Starting"
        }
        guard let lastRun else { return "Not run yet" }
        return "Last run: \(lastRun.title)"
    }

    private var idleFraction: Double {
        guard let lastRun, !lastRun.wasDryRun else { return 0 }
        return switch lastRun.status {
        case .success, .completedWithErrors: 1
        default: 0
        }
    }

    private var detail: String {
        if run != nil { return progress?.currentPath ?? "" }
        guard let lastRun, lastRun.status.hasCounts else { return "" }
        return lastRun.changeSummary
    }

    private var rate: String {
        guard let progress else { return "" }
        if progress.phase == .scanning { return run?.timeLeft ?? "" }

        var parts: [String] = []
        if progress.bytesTotal > 0 {
            parts.append("\(bytes(progress.bytesDone)) of \(bytes(progress.bytesTotal))")
        } else if progress.itemsTotal > 0 {
            parts.append("\(progress.itemsDone) of \(progress.itemsTotal) items")
        }

        // Wait a moment, because the first readings are too noisy to be useful.
        if let run, !run.isPaused, let started = run.copyStartedAt, progress.bytesDone > 0 {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= TimeEstimate.warmUp {
                parts.append("\(bytes(Int64(Double(progress.bytesDone) / elapsed)))/s")
            }
        }
        if let timeLeft = run?.timeLeft { parts.append(timeLeft) }
        return parts.joined(separator: " · ")
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

private struct HistoryRow: View {
    let record: RunRecord

    var body: some View {
        DisclosureGroup {
            if let planned = record.plannedChanges {
                if planned.isEmpty {
                    Text("Nothing would change.")
                        .foregroundStyle(.secondary)
                }
                ForEach(planned, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                let hidden = record.itemsCopied + record.itemsDeleted - planned.count
                if hidden > 0 {
                    Text("And \(hidden) more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if record.errors.isEmpty, record.plannedChanges == nil {
                Text("No errors.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(record.errors, id: \.self) { message in
                    Text(message)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                if record.errorCount > record.errors.count {
                    Text("And \(record.errorCount - record.errors.count) more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack {
                record.icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.title)
                    Text(timing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if record.status.hasCounts {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(record.changeSummary)
                            .monospacedDigit()
                        Text("\(ByteCountFormatter.string(fromByteCount: record.bytesCopied, countStyle: .file)) \(record.wasDryRun ? "to copy" : "copied")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var timing: String {
        let started = record.startedAt.formatted(date: .abbreviated, time: .shortened)
        let seconds = record.finishedAt.timeIntervalSince(record.startedAt)
        guard record.status.hasCounts else { return started }
        if seconds < 1 { return "\(started) · under 1 sec" }
        let duration = Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
        )
        return "\(started) · \(duration)"
    }
}

extension RunRecord {
    /// Records from earlier versions only have combined totals.
    var changeSummary: String {
        guard let filesAdded, let filesReplaced, let filesDeleted else {
            return "\(itemsCopied) items copied, \(itemsDeleted) removed"
        }
        let summary = "\(filesAdded) \(filesAdded == 1 ? "file" : "files") added · \(filesReplaced) replaced · \(filesDeleted) deleted"
        guard wasDryRun else { return summary }
        let unchanged = filesUnchanged.map { " · \($0) unchanged" } ?? ""
        return "Would be: \(summary)\(unchanged)"
    }
}

extension RunRecord.Status {
    /// Runs that never started have nothing to count.
    var hasCounts: Bool {
        self != .failed && self != .skipped
    }
}
