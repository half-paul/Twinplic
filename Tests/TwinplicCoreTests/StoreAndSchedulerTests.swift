import XCTest
@testable import TwinplicCore

final class StoreAndSchedulerTests: XCTestCase {
    private var root: URL!
    private var store: TaskStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TwinplicStore-\(UUID().uuidString)")
        store = TaskStore(directory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTasksRoundTrip() throws {
        let task = BackupTask(name: "Work", sourcePath: "/a", destinationPath: "/b", schedule: .weekly(weekday: 1, hour: 9, minute: 30))

        try store.saveTasks([task])

        XCTAssertEqual(try store.loadTasks(), [task])
    }

    func testMissingFilesLoadAsEmpty() throws {
        XCTAssertEqual(try store.loadTasks(), [])
        XCTAssertEqual(try store.loadHistory(for: UUID()), [])
    }

    func testHistoryIsNewestFirstAndCapped() throws {
        let id = UUID()
        for index in 0..<(TaskStore.maxHistoryPerTask + 5) {
            var record = RunRecord(taskID: id, startedAt: Date(), finishedAt: Date(), status: .success)
            record.itemsCopied = index
            try store.append(record)
        }

        let history = try store.loadHistory(for: id)

        XCTAssertEqual(history.count, TaskStore.maxHistoryPerTask)
        XCTAssertEqual(history.first?.itemsCopied, TaskStore.maxHistoryPerTask + 4)
    }

    func testRunLockBlocksSecondHolderUntilReleased() throws {
        let id = UUID()
        var first = try store.acquireRunLock(for: id)
        XCTAssertNotNil(first)

        XCTAssertNil(try store.acquireRunLock(for: id))

        first = nil
        XCTAssertNotNil(try store.acquireRunLock(for: id))
    }

    func testRunnerRecordsResultAndRefusesOverlap() throws {
        let source = root.appendingPathComponent("s")
        let destination = root.appendingPathComponent("d")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source.appendingPathComponent("a.txt"))
        let task = BackupTask(sourcePath: source.path, destinationPath: destination.path)

        let record = try TaskRunner.run(BackupEngine(task: task), store: store)
        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(try store.loadHistory(for: task.id).count, 1)

        let held = try store.acquireRunLock(for: task.id)
        let blocked = try TaskRunner.run(BackupEngine(task: task), store: store)
        XCTAssertEqual(blocked.status, .failed)
        withExtendedLifetime(held) {}
    }

    func testSyncWritesAgentAndManualRemovesIt() throws {
        let scheduler = LaunchAgentScheduler(agentsDirectory: root, managesLaunchd: false)
        var task = BackupTask(schedule: .daily(hour: 2, minute: 0))
        let plist = root.appendingPathComponent("\(LaunchAgentScheduler.labelPrefix)\(task.id.uuidString).plist")

        try scheduler.sync(task, executablePath: "/Applications/Twinplic.app/Contents/MacOS/Twinplic")

        let parsed = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
        XCTAssertEqual(
            parsed?["ProgramArguments"] as? [String],
            ["/Applications/Twinplic.app/Contents/MacOS/Twinplic", "--run-task", task.id.uuidString]
        )

        task.schedule = .manual
        try scheduler.sync(task, executablePath: "/x")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plist.path))
    }
}
