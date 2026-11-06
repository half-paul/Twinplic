import AppKit
import TwinplicCore
import Foundation
import Observation
import ServiceManagement
import SwiftUI

struct ActiveRun {
    let engine: BackupEngine
    var progress: RunProgress?
    var scanStartedAt: Date?
    var workStartedAt: Date?
    var copyStartedAt: Date?
    var pausedAt: Date?
    /// From the last finished run. Nil means the scan estimate falls back on tree position.
    let expectedDirectories: Int?

    init(engine: BackupEngine, history: [RunRecord]) {
        self.engine = engine
        expectedDirectories = RunRecord.expectedDirectories(from: history)
    }

    mutating func update(with progress: RunProgress) {
        // The engine continues by itself when a pause runs out, and this is the first sign.
        if let pausedAt, !engine.isPaused { resume(pausedSince: pausedAt) }

        let now = Date()
        if progress.phase == .scanning {
            if scanStartedAt == nil { scanStartedAt = now }
        } else if workStartedAt == nil {
            workStartedAt = now
        }
        // Throttling can drop the first copying update, so a verify update also counts.
        if progress.phase == .copying || progress.phase == .verifying, copyStartedAt == nil {
            copyStartedAt = now
        }
        self.progress = progress
    }

    var isPaused: Bool { pausedAt != nil }
    var resumesAt: Date? { pausedAt?.addingTimeInterval(BackupEngine.maxPause) }

    mutating func togglePause() {
        if let pausedAt {
            resume(pausedSince: pausedAt)
        } else if !engine.isCancelled {
            engine.pause()
            pausedAt = Date()
        }
    }

    mutating func stop() {
        engine.cancel()
        if let pausedAt { resume(pausedSince: pausedAt) }
    }

    /// Moves the start times forward, so a pause doesn't count as slow progress.
    private mutating func resume(pausedSince pausedAt: Date) {
        let now = Date()
        let gap = now.timeIntervalSince(pausedAt)
        func shifted(_ date: Date?) -> Date? { date.map { min($0.addingTimeInterval(gap), now) } }
        scanStartedAt = shifted(scanStartedAt)
        workStartedAt = shifted(workStartedAt)
        copyStartedAt = shifted(copyStartedAt)
        self.pausedAt = nil
        engine.resume()
    }

    /// When this phase's measure of progress started moving. Bytes only move once copying
    /// starts, so time spent removing extras would otherwise inflate the estimate.
    private var estimateStartedAt: Date? {
        guard let progress else { return nil }
        if progress.phase == .scanning { return scanStartedAt }
        return progress.bytesTotal > 0 ? copyStartedAt : workStartedAt
    }

    /// Time left in the current stage. A scan can't see the backup that follows it, because
    /// how much will be copied isn't known until the scan ends.
    var timeLeft: String? {
        guard !isPaused, let progress, progress.phase != .finishing, let estimateStartedAt,
              let seconds = TimeEstimate.secondsLeft(
                  progress, elapsed: Date().timeIntervalSince(estimateStartedAt),
                  expectedDirectories: expectedDirectories
              ),
              seconds >= 1
        else { return nil }

        let text = Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
        )
        return progress.phase == .scanning ? "About \(text) left" : "\(text) left"
    }
}

struct PreviewResult: Identifiable {
    let id = UUID()
    let task: BackupTask
    let plan: BackupPlan
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var offersAccessSettings = false
}

/// Keeps per-file progress from flooding the main thread. Always delivers the newest
/// update, because a large file can go quiet for a long time after its first one.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: RunProgress?
    private let deliver: @MainActor @Sendable (RunProgress) -> Void

    init(deliver: @escaping @MainActor @Sendable (RunProgress) -> Void) {
        self.deliver = deliver
    }

    func submit(_ progress: RunProgress) {
        let isFirstInBatch = lock.withLock {
            defer { latest = progress }
            return latest == nil
        }
        guard isFirstInBatch else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            if let newest = takeLatest() { deliver(newest) }
        }
    }

    private func takeLatest() -> RunProgress? {
        lock.withLock {
            defer { latest = nil }
            return latest
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var tasks: [BackupTask] = []
    var selection: UUID?
    var activeRuns: [UUID: ActiveRun] = [:]
    var histories: [UUID: [RunRecord]] = [:]
    var alert: AppAlert?
    var preview: PreviewResult?
    /// A task waiting for the user to approve its unrecognized destination.
    var pendingConsent: BackupTask?
    var launchesAtLogin = SMAppService.mainApp.status == .enabled
    var hasFullDiskAccess = FullDiskAccess.isGranted
    var helpTopic: HelpTopic? = .gettingStarted
    /// The banner stays up, so one alert per launch is enough.
    private var hasAskedForAccess = false

    private let store = TaskStore()
    private let scheduler = LaunchAgentScheduler()

    init() {
        do {
            tasks = try store.loadTasks()
            for task in tasks {
                histories[task.id] = try store.loadHistory(for: task.id)
            }
            selection = tasks.first?.id
            syncAllSchedules()
        } catch {
            show("Couldn't load your backups", error)
        }
    }

    private func show(_ title: String, _ error: Error) {
        alert = AppAlert(title: title, message: error.localizedDescription)
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.isGranted
    }

    func openFullDiskAccessSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: pane), NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple.systempreferences:") { NSWorkspace.shared.open(url) }
    }

    private func askForAccess(after problems: AccessProblems?) {
        guard let problems, problems.privacyBlocked > 0 else { return }
        refreshFullDiskAccess()
        guard hasFullDiskAccess != true, !hasAskedForAccess else { return }
        hasAskedForAccess = true
        alert = AppAlert(
            title: "Twinplic needs Full Disk Access",
            message: "macOS blocked Twinplic from reading some items, so they weren't backed up. Their existing backups weren't touched. Only you can allow this, in System Settings. Turn on Twinplic in the list, then quit and reopen it.",
            offersAccessSettings: true
        )
    }

    private func save() {
        do {
            try store.saveTasks(tasks)
        } catch {
            show("Couldn't save your backups", error)
        }
    }

    private var executablePath: String? { Bundle.main.executablePath }

    private func syncSchedule(_ task: BackupTask) {
        guard let executablePath else { return }
        do {
            try scheduler.sync(task, executablePath: executablePath)
        } catch {
            show("Couldn't update the schedule", error)
        }
    }

    private func syncAllSchedules() {
        tasks.forEach(syncSchedule)
    }

    func refreshLaunchAtLogin() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // `alert` shows in the main window, which may be closed.
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
        refreshLaunchAtLogin()
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func addTask() {
        let task = BackupTask()
        tasks.append(task)
        selection = task.id
        save()
    }

    func delete(_ task: BackupTask) {
        tasks.removeAll { $0.id == task.id }
        histories[task.id] = nil
        if selection == task.id { selection = tasks.first?.id }
        save()
        do {
            try scheduler.remove(taskID: task.id)
            try store.deleteHistory(for: task.id)
        } catch {
            show("Couldn't fully remove this backup", error)
        }
    }

    func binding(for id: UUID) -> Binding<BackupTask>? {
        guard let current = tasks.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.tasks.first { $0.id == id } ?? current },
            set: { [weak self] updated in self?.update(updated) }
        )
    }

    private func update(_ task: BackupTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let scheduleChanged = tasks[index].schedule != task.schedule
        tasks[index] = task
        save()
        if scheduleChanged { syncSchedule(task) }
    }

    func isBusy(_ id: UUID) -> Bool {
        activeRuns[id] != nil
    }

    func makePreview(_ task: BackupTask) {
        guard !isBusy(task.id) else { return }
        // Tracked like a run, so a long scan shows its progress and a Stop button.
        let engine = BackupEngine(task: task)
        let throttle = ProgressThrottle { [weak self] progress in
            self?.record(progress, for: task.id)
        }
        activeRuns[task.id] = ActiveRun(engine: engine, history: histories[task.id] ?? [])

        Task {
            let outcome = await Task.detached { () -> Result<BackupPlan, Error> in
                Result {
                    // Looking is always safe, so consent isn't needed to preview.
                    try engine.preflight(allowUnrecognizedDestination: true)
                    return engine.preview(onScan: throttle.submit)
                }
            }.value

            activeRuns[task.id] = nil
            switch outcome {
            case .success(let plan):
                // A stopped scan is incomplete, so its plan would mislead.
                if !engine.isCancelled { preview = PreviewResult(task: task, plan: plan) }
            case .failure(let error):
                show("Can't preview this backup", error)
                askForAccess(after: AccessProblems(error))
            }
        }
    }

    func start(_ task: BackupTask) {
        guard !isBusy(task.id) else { return }
        let engine = BackupEngine(task: task)
        activeRuns[task.id] = ActiveRun(engine: engine, history: histories[task.id] ?? [])

        Task {
            // Off the main thread, because a slow or sleeping disk can take a while to answer.
            let outcome = await Task.detached { () -> Result<Void, Error> in
                // A dry run writes nothing, so it needs no consent.
                Result { try engine.preflight(allowUnrecognizedDestination: task.dryRun) }
            }.value

            switch outcome {
            case .success:
                run(engine, allowUnrecognizedDestination: false)
            case .failure(PreflightError.unrecognizedDestination):
                activeRuns[task.id] = nil
                pendingConsent = task
            case .failure(let error):
                activeRuns[task.id] = nil
                show("Can't start this backup", error)
                askForAccess(after: AccessProblems(error))
            }
        }
    }

    func confirmPendingRun() {
        guard let task = pendingConsent else { return }
        pendingConsent = nil
        run(BackupEngine(task: task), allowUnrecognizedDestination: true)
    }

    func stop(_ id: UUID) {
        activeRuns[id]?.stop()
    }

    func togglePause(_ id: UUID) {
        activeRuns[id]?.togglePause()
    }

    private func record(_ progress: RunProgress, for id: UUID) {
        activeRuns[id]?.update(with: progress)
    }

    private func reloadHistory(for id: UUID) {
        if let history = try? store.loadHistory(for: id) {
            histories[id] = history
        }
    }

    /// Scheduled runs happen in another process, so pick up what they wrote.
    func reloadHistories() {
        tasks.forEach { reloadHistory(for: $0.id) }
    }

    private func run(_ engine: BackupEngine, allowUnrecognizedDestination: Bool) {
        let task = engine.task
        let store = store
        let throttle = ProgressThrottle { [weak self] progress in
            self?.record(progress, for: task.id)
        }
        // `start` already tracks this engine, and may have been paused during its preflight.
        if activeRuns[task.id]?.engine !== engine {
            activeRuns[task.id] = ActiveRun(engine: engine, history: histories[task.id] ?? [])
        }

        Task {
            let outcome = await Task.detached { () -> Result<RunRecord, Error> in
                Result {
                    try TaskRunner.run(engine, store: store, allowUnrecognizedDestination: allowUnrecognizedDestination) { progress in
                        throttle.submit(progress)
                    }
                }
            }.value

            activeRuns[task.id] = nil
            switch outcome {
            case .success(let record):
                reloadHistory(for: task.id)
                if record.status == .failed, let message = record.errors.first {
                    alert = AppAlert(title: "Backup didn't run", message: message)
                }
                askForAccess(after: record.access)
            case .failure(let error):
                show("Backup failed", error)
            }
        }
    }
}
