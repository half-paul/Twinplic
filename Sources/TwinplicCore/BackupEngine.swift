import CryptoKit
import Darwin
import Foundation

public final class BackupEngine: @unchecked Sendable {
    /// A paused run carries on by itself after this long, so a forgotten pause can't
    /// leave a backup unfinished.
    public static let maxPause: TimeInterval = 15 * 60

    public let task: BackupTask

    private let allowClones: Bool
    /// Guards the flags below, and wakes a paused run.
    private let control = NSCondition()
    private var cancelled = false
    private var paused = false
    private var pauseEnds = Date.distantPast
    private var pausesTaken = 0

    /// `allowClones: false` forces real data copies, even within one APFS volume.
    public init(task: BackupTask, allowClones: Bool = true) {
        self.task = task
        self.allowClones = allowClones
    }

    public func cancel() {
        control.withLock {
            cancelled = true
            paused = false
            control.broadcast()
        }
    }

    public var isCancelled: Bool {
        control.withLock { cancelled }
    }

    /// The run stops at its next checkpoint and sleeps there, using no CPU, until
    /// `resume()`, `cancel()` or the time runs out.
    public func pause(for duration: TimeInterval = BackupEngine.maxPause) {
        control.withLock {
            guard !cancelled else { return }
            paused = true
            pauseEnds = Date().addingTimeInterval(duration)
        }
    }

    public func resume() {
        control.withLock {
            paused = false
            control.broadcast()
        }
    }

    public var isPaused: Bool {
        control.withLock { paused && Date() < pauseEnds }
    }

    private func waitWhilePaused() {
        control.withLock {
            guard paused else { return }
            pausesTaken += 1
            while paused, Date() < pauseEnds {
                _ = control.wait(until: pauseEnds)
            }
            paused = false
        }
    }

    /// The checkpoint for everything long-running: sleeps through a pause, then says
    /// whether to give up.
    private func shouldStop() -> Bool {
        waitWhilePaused()
        return isCancelled
    }

    /// Throws `PreflightError` if the task is unsafe to run as configured.
    public func preflight(allowUnrecognizedDestination: Bool = false) throws {
        try Preflight.check(task, allowUnrecognizedDestination: allowUnrecognizedDestination)
    }

    /// Lists what a run would change. Reads only.
    public func preview(onScan: @escaping @Sendable (RunProgress) -> Void = { _ in }) -> BackupPlan {
        Planner(task: task, isCancelled: { [weak self] in self?.shouldStop() ?? true }, onScan: onScan).makePlan()
    }

    public func run(
        allowUnrecognizedDestination: Bool = false,
        progress: @escaping @Sendable (RunProgress) -> Void = { _ in }
    ) -> RunRecord {
        let startedAt = Date()
        var record = RunRecord(taskID: task.id, startedAt: startedAt, finishedAt: startedAt, status: .success)
        if task.dryRun { record.isDryRun = true }

        do {
            // A dry run writes nothing, so it can't harm an unrecognized destination.
            try preflight(allowUnrecognizedDestination: allowUnrecognizedDestination || task.dryRun)
        } catch {
            record.addError(error.localizedDescription)
            record.noteAccess(error)
            record.status = .failed
            record.finishedAt = Date()
            return record
        }

        let plan = preview(onScan: progress)
        plan.errors.forEach { record.addError($0) }
        // A stopped scan only saw part of the tree, so its count would mislead.
        if !isCancelled { record.filesUnchanged = plan.unchangedCount }
        if !plan.access.isEmpty { record.access = plan.access }
        record.directoriesScanned = plan.directoriesScanned

        if !isCancelled {
            if task.dryRun {
                simulate(plan, record: &record, progress: progress)
            } else {
                execute(plan, record: &record, progress: progress)
            }
        }

        if isCancelled {
            record.status = .cancelled
        } else if record.errorCount > 0 {
            record.status = .completedWithErrors
        }
        record.finishedAt = Date()
        return record
    }

    /// Counts a plan the way `execute` would, without touching the destination.
    private func simulate(
        _ plan: BackupPlan, record: inout RunRecord, progress: @escaping @Sendable (RunProgress) -> Void
    ) {
        var state = RunProgress(
            phase: .simulating, currentPath: "", itemsDone: 0, itemsTotal: plan.items.count,
            bytesDone: 0, bytesTotal: plan.bytesToCopy
        )
        record.plannedChanges = []

        for item in plan.items {
            if shouldStop() { return }
            state.currentPath = item.relativePath
            progress(state)

            switch item.action {
            case .delete:
                record.itemsDeleted += 1
                record.filesDeleted? += item.fileCount
                record.addPlannedChange("Delete \(item.relativePath)")
            case .copyNew:
                record.itemsCopied += 1
                record.filesAdded? += item.fileCount
                record.addPlannedChange("Add \(item.relativePath)")
            case .update:
                record.itemsCopied += 1
                record.filesReplaced? += item.fileCount
                record.addPlannedChange("Replace \(item.relativePath)")
            }
            if item.action != .delete, item.kind == .file {
                record.bytesCopied += item.size
                state.bytesDone += item.size
            }
            state.itemsDone += 1
        }
    }

    private func execute(
        _ plan: BackupPlan, record: inout RunRecord, progress: @escaping @Sendable (RunProgress) -> Void
    ) {
        do {
            try writeMarker()
        } catch {
            record.addError("Could not write to \(task.destinationPath): \(error.localizedDescription)")
            record.noteAccess(error)
            return
        }

        let safetyNet = task.safetyNetEnabled ? SafetyNet(destinationPath: task.destinationPath) : nil
        var state = RunProgress(
            phase: .removing, currentPath: "", itemsDone: 0, itemsTotal: plan.items.count,
            bytesDone: 0, bytesTotal: plan.bytesToCopy
        )
        // Parents of anything we touch get their timestamps reset at the end.
        var touchedDirectories = Set<String>()

        for item in plan.items where item.action == .delete {
            if shouldStop() { return }
            state.currentPath = item.relativePath
            progress(state)
            do {
                try remove(item.relativePath, safetyNet: safetyNet)
                record.itemsDeleted += 1
                record.filesDeleted? += item.fileCount
                touchedDirectories.insert(parent(of: item.relativePath))
            } catch {
                record.addError("Could not remove \(item.relativePath): \(error.localizedDescription)")
                record.noteAccess(error)
            }
            state.itemsDone += 1
        }

        state.phase = .copying
        for item in plan.items where item.action != .delete {
            if shouldStop() { break }
            state.currentPath = item.relativePath
            progress(state)
            do {
                try copy(
                    item, safetyNet: safetyNet,
                    onBytes: { copied in
                        var current = state
                        current.bytesDone += copied
                        progress(current)
                    },
                    onVerify: {
                        var current = state
                        current.phase = .verifying
                        current.bytesDone += item.size
                        progress(current)
                    }
                )
                record.itemsCopied += 1
                if item.action == .copyNew {
                    record.filesAdded? += item.fileCount
                } else {
                    record.filesReplaced? += item.fileCount
                }
                if item.kind == .file { record.bytesCopied += item.size }
                touchedDirectories.insert(parent(of: item.relativePath))
                if item.kind == .directory { touchedDirectories.insert(item.relativePath) }
            } catch {
                // Stopping mid-file is what the user asked for, not a failure.
                if !isCancelled {
                    record.addError("Could not copy \(item.relativePath): \(error.localizedDescription)")
                    record.noteAccess(error)
                }
            }
            state.itemsDone += 1
            if item.kind == .file { state.bytesDone += item.size }
        }

        state.phase = .finishing
        state.currentPath = ""
        progress(state)

        // Deepest first, because writing into a folder updates that folder's own time.
        let ordered = touchedDirectories.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        for directory in ordered {
            waitWhilePaused()
            do {
                try copyMetadata(relativePath: directory)
            } catch {
                record.addError("Could not set attributes on \(directory): \(error.localizedDescription)")
                record.noteAccess(error)
            }
        }

        if !isCancelled, task.safetyNetEnabled {
            do {
                try SafetyNet.prune(destinationPath: task.destinationPath, retentionDays: task.safetyNetRetentionDays)
            } catch {
                record.addError("Could not clean up SafetyNet: \(error.localizedDescription)")
            }
        }
    }

    private func writeMarker() throws {
        let path = joinPath(task.destinationPath, Reserved.markerFile)
        try Data(task.id.uuidString.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func parent(of relativePath: String) -> String {
        (relativePath as NSString).deletingLastPathComponent
    }

    private func remove(_ relativePath: String, safetyNet: SafetyNet?) throws {
        let name = (relativePath as NSString).lastPathComponent
        if let safetyNet, !name.hasPrefix(Reserved.tempPrefix) {
            try safetyNet.preserve(relativePath: relativePath)
        } else {
            try FileManager.default.removeItem(atPath: joinPath(task.destinationPath, relativePath))
        }
    }

    private func copy(
        _ item: PlanItem, safetyNet: SafetyNet?,
        onBytes: @escaping (Int64) -> Void, onVerify: () -> Void
    ) throws {
        let source = joinPath(task.sourcePath, item.relativePath)
        let destination = joinPath(task.destinationPath, item.relativePath)

        if item.kind == .directory {
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: false)
            return
        }

        // Copy beside the target, then rename: an interrupted run never leaves a
        // half-written file under the real name, and the old version survives until
        // the new one is complete and verified.
        let directory = (destination as NSString).deletingLastPathComponent
        let temporary = joinPath(directory, Reserved.tempPrefix + UUID().uuidString)
        defer { unlink(temporary) }

        let sourceBefore = FileEntry.read(source)
        let pausesBefore = control.withLock { pausesTaken }

        try copyFile(
            from: source, to: temporary,
            flags: allowClones ? copyFileFlagsClone : copyFileFlagsAll,
            onBytes: onBytes
        )

        if task.verifyCopies, item.kind == .file {
            onVerify()
            guard try sha256(of: source) == sha256(of: temporary) else {
                throw CopyError.verificationFailed
            }
        }

        // A file edited during a pause would be part old and part new, yet carry the new
        // modification time, so later runs would never replace it.
        if control.withLock({ pausesTaken }) != pausesBefore {
            let sourceAfter = FileEntry.read(source)
            guard sourceAfter?.size == sourceBefore?.size, sourceAfter?.modified == sourceBefore?.modified else {
                throw CopyError.changedWhilePaused
            }
        }

        if item.action == .update, let safetyNet {
            try safetyNet.preserve(relativePath: item.relativePath)
        }

        guard rename(temporary, destination) == 0 else {
            throw CopyError.posix(errno)
        }
    }

    private func copyMetadata(relativePath: String) throws {
        try copyFile(
            from: joinPath(task.sourcePath, relativePath),
            to: joinPath(task.destinationPath, relativePath),
            flags: copyFileFlagsMetadata
        )
    }

    private func copyFile(
        from source: String, to destination: String, flags: copyfile_flags_t,
        onBytes: ((Int64) -> Void)? = nil
    ) throws {
        guard let onBytes else {
            guard copyfile(source, destination, nil, flags) == 0 else {
                throw CopyError.posix(errno)
            }
            return
        }

        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let context = CopyContext(shouldStop: { [weak self] in self?.shouldStop() ?? true }, onBytes: onBytes)

        try withExtendedLifetime(context) {
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(copyProgressCallback, to: UnsafeRawPointer.self))
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(context).toOpaque())
            guard copyfile(source, destination, state, flags) == 0 else {
                throw CopyError.posix(errno)
            }
        }
    }

    private func sha256(of path: String) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            if shouldStop() { throw CopyError.cancelled }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }
}

enum CopyError: LocalizedError {
    case system(String)
    case posix(Int32)
    case verificationFailed
    case changedWhilePaused
    case cancelled

    var errorDescription: String? {
        switch self {
        case .system(let message): message
        case .posix(let code): errnoMessage(code)
        case .verificationFailed: "The copy doesn't match the original."
        case .changedWhilePaused: "It changed while the run was paused, so it will be copied on the next run."
        case .cancelled: "Cancelled."
        }
    }
}

private let copyFileFlagsMetadata = copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW)
private let copyFileFlagsAll = copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW)
private let copyFileFlagsClone = copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | COPYFILE_CLONE)

private final class CopyContext {
    let shouldStop: () -> Bool
    let onBytes: (Int64) -> Void

    init(shouldStop: @escaping () -> Bool, onBytes: @escaping (Int64) -> Void) {
        self.shouldStop = shouldStop
        self.onBytes = onBytes
    }
}

/// Called by copyfile(3) between chunks, which also lets Stop and Pause interrupt a large file.
private let copyProgressCallback: copyfile_callback_t = { what, stage, state, _, _, context in
    guard what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let state, let context else {
        return COPYFILE_CONTINUE
    }
    let copyContext = Unmanaged<CopyContext>.fromOpaque(context).takeUnretainedValue()
    if copyContext.shouldStop() { return COPYFILE_QUIT }

    var copied: off_t = 0
    if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
        copyContext.onBytes(Int64(copied))
    }
    return COPYFILE_CONTINUE
}
