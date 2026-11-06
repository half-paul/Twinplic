import XCTest
@testable import TwinplicCore

final class PauseTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("TwinplicPause-\(UUID().uuidString)")
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

    private var largeFile: URL { source.appendingPathComponent("large.bin") }
    private var copiedFile: URL { destination.appendingPathComponent("large.bin") }

    private func writeLargeFile() throws {
        try Data(repeating: 7, count: 64 * 1024 * 1024).write(to: largeFile)
    }

    /// Starts a run that pauses itself part way through the large file.
    private func runPausingMidFile(_ engine: BackupEngine) -> (paused: DispatchSemaphore, finished: RunBox) {
        let paused = DispatchSemaphore(value: 0)
        let box = RunBox()
        let once = Once()
        DispatchQueue.global().async {
            box.record = engine.run { progress in
                if progress.bytesDone > 0, once.first() {
                    engine.pause()
                    paused.signal()
                }
            }
            box.done.signal()
        }
        return (paused, box)
    }

    func testContinueFinishesAFilePausedPartWay() throws {
        try writeLargeFile()
        let engine = BackupEngine(task: task, allowClones: false)
        let run = runPausingMidFile(engine)

        XCTAssertEqual(run.paused.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(engine.isPaused)
        XCTAssertEqual(run.finished.done.wait(timeout: .now() + 0.3), .timedOut, "A paused run must not finish")
        XCTAssertFalse(fileManager.fileExists(atPath: copiedFile.path))

        engine.resume()
        XCTAssertEqual(run.finished.done.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(run.finished.record?.status, .success, run.finished.record?.errors.joined() ?? "")
        XCTAssertEqual(try Data(contentsOf: copiedFile), try Data(contentsOf: largeFile))
    }

    func testStopEndsAPausedRun() throws {
        try writeLargeFile()
        let engine = BackupEngine(task: task, allowClones: false)
        let run = runPausingMidFile(engine)

        XCTAssertEqual(run.paused.wait(timeout: .now() + 10), .success)
        engine.cancel()

        XCTAssertEqual(run.finished.done.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(run.finished.record?.status, .cancelled)
        XCTAssertEqual(run.finished.record?.errorCount, 0)
        XCTAssertFalse(engine.isPaused)
        let names = try fileManager.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(names.filter { $0 != Reserved.markerFile }, [], "No partial file should remain")
    }

    func testFileEditedDuringAPauseIsNotBackedUpHalfChanged() throws {
        try writeLargeFile()
        let engine = BackupEngine(task: task, allowClones: false)
        let run = runPausingMidFile(engine)

        XCTAssertEqual(run.paused.wait(timeout: .now() + 10), .success)
        // Wait out the run's way to the checkpoint, so the edit lands inside the pause.
        Thread.sleep(forTimeInterval: 0.2)
        try Data(repeating: 9, count: 1024).write(to: largeFile)
        engine.resume()

        XCTAssertEqual(run.finished.done.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(run.finished.record?.status, .completedWithErrors)
        XCTAssertFalse(fileManager.fileExists(atPath: copiedFile.path), "A mixed copy must not reach the backup")

        let retry = BackupEngine(task: task, allowClones: false).run()
        XCTAssertEqual(retry.status, .success, retry.errors.joined())
        XCTAssertEqual(try Data(contentsOf: copiedFile), try Data(contentsOf: largeFile))
    }

    func testPauseHoldsAScan() throws {
        try Data("data".utf8).write(to: source.appendingPathComponent("a.txt"))
        let engine = BackupEngine(task: task)
        engine.pause()

        let box = RunBox()
        DispatchQueue.global().async {
            box.record = engine.run()
            box.done.signal()
        }

        XCTAssertEqual(box.done.wait(timeout: .now() + 0.3), .timedOut)
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("a.txt").path))

        engine.resume()
        XCTAssertEqual(box.done.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(box.record?.status, .success)
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("a.txt").path))
    }

    func testPausesLastFifteenMinutes() {
        XCTAssertEqual(BackupEngine.maxPause, 900)
    }

    func testPausedRunContinuesByItself() throws {
        try Data("data".utf8).write(to: source.appendingPathComponent("a.txt"))
        let engine = BackupEngine(task: task)
        engine.pause(for: 0.5)

        let box = RunBox()
        DispatchQueue.global().async {
            box.record = engine.run()
            box.done.signal()
        }

        XCTAssertEqual(box.done.wait(timeout: .now() + 0.2), .timedOut, "It should still be paused")
        XCTAssertTrue(engine.isPaused)
        XCTAssertEqual(box.done.wait(timeout: .now() + 10), .success, "Nobody resumed it, so the time limit must")
        XCTAssertEqual(box.record?.status, .success)
        XCTAssertFalse(engine.isPaused)
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("a.txt").path))
    }

    func testPausingAgainRestartsTheTime() throws {
        try Data("data".utf8).write(to: source.appendingPathComponent("a.txt"))
        let engine = BackupEngine(task: task)
        engine.pause(for: 0.3)

        let box = RunBox()
        DispatchQueue.global().async {
            box.record = engine.run()
            box.done.signal()
        }

        Thread.sleep(forTimeInterval: 0.1)
        engine.resume()
        engine.pause(for: 60)
        XCTAssertEqual(box.done.wait(timeout: .now() + 0.6), .timedOut, "The first time limit no longer applies")

        engine.resume()
        XCTAssertEqual(box.done.wait(timeout: .now() + 10), .success)
    }

    func testPauseEndsEvenIfTheRunNeverReachedACheckpoint() {
        let engine = BackupEngine(task: task)
        engine.pause(for: 0.05)
        XCTAssertTrue(engine.isPaused)
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(engine.isPaused)
    }

    func testPauseAfterStopIsIgnored() {
        let engine = BackupEngine(task: task)
        engine.cancel()
        engine.pause()
        XCTAssertFalse(engine.isPaused)
    }
}

private final class RunBox: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    var record: RunRecord?
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func first() -> Bool {
        lock.withLock {
            defer { used = true }
            return !used
        }
    }
}
