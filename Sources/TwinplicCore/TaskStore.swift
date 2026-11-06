import Darwin
import Foundation

/// Saves tasks and run history as JSON. History is one file per task, so the per-task
/// run lock also protects it when the app and a scheduled run are both active.
public struct TaskStore: Sendable {
    public static let maxHistoryPerTask = 50

    public let directory: URL

    public init(directory: URL = TaskStore.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Twinplic", isDirectory: true)
    }

    private var tasksFile: URL { directory.appendingPathComponent("tasks.json") }

    private func historyFile(for id: UUID) -> URL {
        directory.appendingPathComponent("history", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).json")
    }

    private func save(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    public func loadTasks() throws -> [BackupTask] {
        try load([BackupTask].self, from: tasksFile) ?? []
    }

    public func saveTasks(_ tasks: [BackupTask]) throws {
        try save(tasks, to: tasksFile)
    }

    /// Newest first.
    public func loadHistory(for id: UUID) throws -> [RunRecord] {
        try load([RunRecord].self, from: historyFile(for: id)) ?? []
    }

    public func append(_ record: RunRecord) throws {
        var history = try loadHistory(for: record.taskID)
        history.insert(record, at: 0)
        try save(Array(history.prefix(Self.maxHistoryPerTask)), to: historyFile(for: record.taskID))
    }

    public func deleteHistory(for id: UUID) throws {
        let url = historyFile(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Takes a lock held for as long as the returned object lives. The kernel releases
    /// it if the process dies, so a crash can't leave a task stuck. Returns nil if the
    /// task is already running.
    public func acquireRunLock(for id: UUID) throws -> RunLock? {
        let folder = directory.appendingPathComponent("locks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.appendingPathComponent(id.uuidString).path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { throw CopyError.system(errnoMessage()) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return RunLock(descriptor: descriptor)
    }
}

public final class RunLock: Sendable {
    private let descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }
}

/// Runs a task under its lock and records the result. Used by the app and by launchd.
public enum TaskRunner {
    /// The launchd entry point: applies the conditions that only limit scheduled runs.
    public static func runScheduled(
        _ engine: BackupEngine,
        store: TaskStore,
        isOnBattery: () -> Bool = PowerState.isOnBattery,
        progress: @escaping @Sendable (RunProgress) -> Void = { _ in }
    ) throws -> RunRecord {
        guard engine.task.skipOnBattery, isOnBattery() else {
            return try run(engine, store: store, progress: progress)
        }
        var record = RunRecord(taskID: engine.task.id, startedAt: Date(), finishedAt: Date(), status: .skipped)
        record.addError("Skipped because the Mac was on battery power.")
        guard let lock = try store.acquireRunLock(for: engine.task.id) else { return record }
        try withExtendedLifetime(lock) { try store.append(record) }
        return record
    }

    public static func run(
        _ engine: BackupEngine,
        store: TaskStore,
        allowUnrecognizedDestination: Bool = false,
        progress: @escaping @Sendable (RunProgress) -> Void = { _ in }
    ) throws -> RunRecord {
        guard let lock = try store.acquireRunLock(for: engine.task.id) else {
            var record = RunRecord(taskID: engine.task.id, startedAt: Date(), finishedAt: Date(), status: .failed)
            record.addError("This backup is already running.")
            return record
        }
        return try withExtendedLifetime(lock) {
            let record = engine.run(allowUnrecognizedDestination: allowUnrecognizedDestination, progress: progress)
            try store.append(record)
            return record
        }
    }
}
