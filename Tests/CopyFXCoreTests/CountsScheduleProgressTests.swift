import XCTest
@testable import CopyFXCore

final class CountsScheduleProgressTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("CopyFXCounts-\(UUID().uuidString)")
        source = root.appendingPathComponent("source")
        destination = root.appendingPathComponent("destination")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private var task: BackupTask {
        BackupTask(sourcePath: source.path, destinationPath: destination.path, excludes: [])
    }

    private func write(_ text: String, _ path: String) throws {
        let url = source.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    // MARK: Run counts

    func testRunCountsAddedReplacedAndDeletedFiles() throws {
        try write("one", "keep.txt")
        try write("two", "change.txt")
        try write("three", "old/a.txt")
        try write("four", "old/deep/b.txt")
        try write("five", "gone.txt")

        let first = BackupEngine(task: task).run()
        XCTAssertEqual(first.filesAdded, 5, "Folders aren't counted as files")
        XCTAssertEqual(first.filesReplaced, 0)
        XCTAssertEqual(first.filesDeleted, 0)

        try fileManager.removeItem(at: source.appendingPathComponent("old"))
        try fileManager.removeItem(at: source.appendingPathComponent("gone.txt"))
        try write("two, longer", "change.txt")
        try write("new", "fresh.txt")

        let plan = BackupEngine(task: task).preview()
        XCTAssertEqual([plan.copyCount, plan.updateCount, plan.deleteCount], [1, 1, 3])

        let second = BackupEngine(task: task).run()
        XCTAssertEqual(second.status, .success, second.errors.joined())
        XCTAssertEqual(second.filesAdded, 1)
        XCTAssertEqual(second.filesReplaced, 1)
        XCTAssertEqual(second.filesDeleted, 3, "A deleted folder counts the files inside it")
    }

    func testFileBecomingSymlinkCountsAsReplaced() throws {
        try write("data", "item")
        _ = BackupEngine(task: task).run()
        let item = source.appendingPathComponent("item").path
        try fileManager.removeItem(atPath: item)
        try fileManager.createSymbolicLink(atPath: item, withDestinationPath: "elsewhere")

        let record = BackupEngine(task: task).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(record.filesReplaced, 1)
        XCTAssertEqual(record.filesDeleted, 0)
        XCTAssertEqual(
            try fileManager.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("item").path),
            "elsewhere"
        )
    }

    func testStaleTemporaryFileIsNotCountedAsDeleted() throws {
        try write("one", "a.txt")
        _ = BackupEngine(task: task).run()
        try Data("partial".utf8).write(to: destination.appendingPathComponent(Reserved.tempPrefix + "stale"))

        let record = BackupEngine(task: task).run()

        XCTAssertEqual(record.filesDeleted, 0)
    }

    // MARK: Relative paths

    func testTopLevelItemsHaveNoLeadingSlash() throws {
        try write("one", "a.txt")

        let plan = BackupEngine(task: task).preview()

        XCTAssertEqual(plan.items.map(\.relativePath), ["a.txt"])
    }

    func testPathPatternExcludesAtTopLevel() throws {
        try write("skip", "cache/b.tmp")
        try write("keep", "cache/c.txt")
        var excluding = task
        excluding.excludes = ["cache/*.tmp"]

        let record = BackupEngine(task: excluding).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("cache/b.tmp").path))
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("cache/c.txt").path))
    }

    func testRunLeavesDestinationRootAttributesAlone() throws {
        try write("one", "a.txt")
        XCTAssertEqual(chmod(source.path, 0o700), 0)
        XCTAssertEqual(chmod(destination.path, 0o755), 0)

        let record = BackupEngine(task: task).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        let attributes = try fileManager.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    // MARK: Saved data from earlier versions

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testRecordFromEarlierVersionLoadsWithoutCounts() throws {
        let json = """
        {"id":"\(UUID().uuidString)","taskID":"\(UUID().uuidString)",
         "startedAt":"2026-11-05T10:00:00Z","finishedAt":"2026-11-05T10:01:00Z",
         "status":"success","itemsCopied":6,"itemsDeleted":1,"bytesCopied":15,
         "errors":[],"errorCount":0}
        """

        let record = try decoder().decode(RunRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.itemsCopied, 6)
        XCTAssertNil(record.filesAdded)
    }

    func testTaskFromEarlierVersionLoads() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","sourcePath":"/a","destinationPath":"/b",
         "deleteExtras":true,"safetyNetEnabled":true,"safetyNetRetentionDays":30,
         "verifyCopies":false,"excludes":[],
         "schedule":{"weekly":{"weekday":1,"hour":9,"minute":30}}}
        """

        let task = try decoder().decode(BackupTask.self, from: Data(json.utf8))

        XCTAssertFalse(task.skipOnBattery)
        XCTAssertEqual(task.schedule.normalized, .weekdays(days: [1], times: [ScheduleTime(hour: 9, minute: 30)]))
    }

    func testNewScheduleRoundTrips() throws {
        let schedule = Schedule.monthDays(days: [1, 15], times: [ScheduleTime(hour: 8, minute: 5)])
        let decoded = try JSONDecoder().decode(Schedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(decoded, schedule)
    }

    // MARK: Schedules

    func testCalendarEntries() {
        let morning = ScheduleTime(hour: 9, minute: 0)
        let evening = ScheduleTime(hour: 18, minute: 30)

        XCTAssertEqual(Schedule.manual.calendarEntries, [])
        XCTAssertEqual(Schedule.interval(minutes: 30).calendarEntries, [])
        XCTAssertEqual(Schedule.hourly(minute: 5).calendarEntries, [["Minute": 5]])
        XCTAssertEqual(Schedule.daily(hour: 2, minute: 0).calendarEntries, [["Hour": 2, "Minute": 0]])
        XCTAssertEqual(
            Schedule.weekdays(days: [3, 1], times: [evening, morning]).calendarEntries,
            [
                ["Weekday": 1, "Hour": 9, "Minute": 0], ["Weekday": 1, "Hour": 18, "Minute": 30],
                ["Weekday": 3, "Hour": 9, "Minute": 0], ["Weekday": 3, "Hour": 18, "Minute": 30],
            ]
        )
        XCTAssertEqual(
            Schedule.weekdays(days: Schedule.allWeekdays, times: [morning]).calendarEntries,
            [["Hour": 9, "Minute": 0]]
        )
        XCTAssertEqual(Schedule.monthDays(days: [15], times: [morning]).calendarEntries, [["Day": 15, "Hour": 9, "Minute": 0]])
        XCTAssertEqual(Schedule.weekdays(days: [], times: [morning]).calendarEntries, [])
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testNextRunPicksSoonestMatch() throws {
        // 2026-11-05 is a Thursday. Monday is 1 and Friday is 5.
        let now = try date("2026-11-05T12:00:00Z")
        let schedule = Schedule.weekdays(days: [1, 5], times: [ScheduleTime(hour: 9, minute: 0)])

        XCTAssertEqual(schedule.nextRun(after: now, calendar: utc), try date("2026-11-06T09:00:00Z"))
    }

    func testNextRunLaterToday() throws {
        let now = try date("2026-11-05T12:00:00Z")
        let schedule = Schedule.weekdays(
            days: Schedule.allWeekdays,
            times: [ScheduleTime(hour: 9, minute: 0), ScheduleTime(hour: 18, minute: 0)]
        )

        XCTAssertEqual(schedule.nextRun(after: now, calendar: utc), try date("2026-11-05T18:00:00Z"))
    }

    func testNextRunSkipsMonthsWithoutThatDay() throws {
        let now = try date("2027-02-01T00:00:00Z")
        let schedule = Schedule.monthDays(days: [30], times: [ScheduleTime(hour: 9, minute: 0)])

        XCTAssertEqual(schedule.nextRun(after: now, calendar: utc), try date("2027-03-30T09:00:00Z"))
    }

    func testIntervalAndManualHaveNoNextRun() {
        XCTAssertNil(Schedule.manual.nextRun())
        XCTAssertNil(Schedule.interval(minutes: 30).nextRun())
    }

    func testAgentPlists() throws {
        let scheduler = LaunchAgentScheduler(agentsDirectory: root, managesLaunchd: false)

        func parsed(_ schedule: Schedule) throws -> [String: Any]? {
            guard let data = try scheduler.plistData(for: BackupTask(schedule: schedule), executablePath: "/x") else { return nil }
            return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        }

        XCTAssertEqual(try parsed(.interval(minutes: 90))?["StartInterval"] as? Int, 5400)
        let times = [ScheduleTime(hour: 1, minute: 0), ScheduleTime(hour: 2, minute: 0)]
        let entries = try parsed(.monthDays(days: [1], times: times))?["StartCalendarInterval"] as? [[String: Int]]
        XCTAssertEqual(entries?.count, 2)
        XCTAssertNil(try parsed(.manual))
        XCTAssertNil(try parsed(.weekdays(days: [], times: times)), "A schedule that can never fire gets no agent")
    }

    func testScheduledRunSkipsOnBatteryAndRecordsIt() throws {
        try write("one", "a.txt")
        let store = TaskStore(directory: root.appendingPathComponent("support"))
        var skipping = task
        skipping.skipOnBattery = true

        let skipped = try TaskRunner.runScheduled(BackupEngine(task: skipping), store: store, isOnBattery: { true })
        XCTAssertEqual(skipped.status, .skipped)
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("a.txt").path))
        XCTAssertEqual(try store.loadHistory(for: skipping.id).first?.status, .skipped)

        let plugged = try TaskRunner.runScheduled(BackupEngine(task: skipping), store: store, isOnBattery: { false })
        XCTAssertEqual(plugged.status, .success, plugged.errors.joined())

        var ignoring = task
        ignoring.skipOnBattery = false
        try fileManager.removeItem(at: destination.appendingPathComponent("a.txt"))
        let ignored = try TaskRunner.runScheduled(BackupEngine(task: ignoring), store: store, isOnBattery: { true })
        XCTAssertEqual(ignored.status, .success, ignored.errors.joined())
    }

    // MARK: Progress

    private func writeLargeFile(_ megabytes: Int) throws -> Int64 {
        let size = megabytes * 1024 * 1024
        try Data(repeating: 7, count: size).write(to: source.appendingPathComponent("large.bin"))
        return Int64(size)
    }

    func testProgressMovesWithinALargeFile() throws {
        let size = try writeLargeFile(64)
        let seen = Locked<[Int64]>([])

        let record = BackupEngine(task: task, allowClones: false).run { progress in
            if progress.phase == .copying { seen.update { $0.append(progress.bytesDone) } }
        }

        XCTAssertEqual(record.status, .success, record.errors.joined())
        let partial = seen.value.filter { $0 > 0 && $0 < size }
        XCTAssertFalse(partial.isEmpty, "Expected updates part way through the file: \(seen.value)")
        XCTAssertEqual(seen.value, seen.value.sorted(), "Progress should never move backwards")
    }

    func testStopInterruptsALargeFileCleanly() throws {
        _ = try writeLargeFile(64)
        let engine = BackupEngine(task: task, allowClones: false)

        let record = engine.run { progress in
            if progress.bytesDone > 0 { engine.cancel() }
        }

        XCTAssertEqual(record.status, .cancelled)
        XCTAssertEqual(record.errorCount, 0)
        let names = try fileManager.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(names.filter { $0 != Reserved.markerFile }, [], "No partial file should remain")
    }

    func testVerifyingPhaseIsReported() throws {
        try write("data", "a.txt")
        var verifying = task
        verifying.verifyCopies = true
        let phases = Locked<[RunProgress.Phase]>([])

        _ = BackupEngine(task: verifying).run { progress in phases.update { $0.append(progress.phase) } }

        XCTAssertTrue(phases.value.contains(.verifying))
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value { lock.withLock { stored } }

    func update(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }
}
