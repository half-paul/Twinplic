import XCTest
@testable import TwinplicCore

final class TimeEstimateTests: XCTestCase {
    private func copying(bytes: Int64, of total: Int64, items: Int = 0, of itemsTotal: Int = 0) -> RunProgress {
        RunProgress(
            phase: .copying, currentPath: "", itemsDone: items, itemsTotal: itemsTotal,
            bytesDone: bytes, bytesTotal: total
        )
    }

    func testCopyEstimateFollowsTheAverageSpeed() throws {
        let left = try XCTUnwrap(TimeEstimate.secondsLeft(copying(bytes: 25, of: 100), elapsed: 10))
        XCTAssertEqual(left, 30, accuracy: 0.001)
    }

    func testItemsAreUsedWhenThereAreNoBytesToCopy() throws {
        let left = try XCTUnwrap(TimeEstimate.secondsLeft(copying(bytes: 0, of: 0, items: 5, of: 10), elapsed: 20))
        XCTAssertEqual(left, 20, accuracy: 0.001)
    }

    func testNoEstimateDuringWarmUpOrBeforeAnyProgress() {
        XCTAssertNil(TimeEstimate.secondsLeft(copying(bytes: 50, of: 100), elapsed: 1))
        XCTAssertNil(TimeEstimate.secondsLeft(copying(bytes: 0, of: 100), elapsed: 60))
    }

    func testScanUsesTheLastRunsFolderCount() throws {
        let scan = RunProgress.scanning("a", directoriesDone: 100, position: 0.9)
        let left = try XCTUnwrap(TimeEstimate.secondsLeft(scan, elapsed: 10, expectedDirectories: 400))
        XCTAssertEqual(left, 30, accuracy: 0.001)
    }

    func testScanFallsBackOnTreePositionWithoutHistory() throws {
        let scan = RunProgress.scanning("a", directoriesDone: 100, position: 0.5)
        let left = try XCTUnwrap(TimeEstimate.secondsLeft(scan, elapsed: 10))
        XCTAssertEqual(left, 10, accuracy: 0.001)
    }

    func testScanThatOutgrowsTheLastRunIsNeverShownAsFinished() throws {
        let scan = RunProgress.scanning("a", directoriesDone: 500, position: 0)
        let left = try XCTUnwrap(TimeEstimate.secondsLeft(scan, elapsed: 100, expectedDirectories: 400))
        XCTAssertGreaterThan(left, 0)
    }

    func testExpectedDirectoriesSkipsRunsThatDidNotFinishTheirScan() {
        func record(_ status: RunRecord.Status, _ directories: Int?) -> RunRecord {
            var record = RunRecord(taskID: UUID(), startedAt: Date(), finishedAt: Date(), status: status)
            record.directoriesScanned = directories
            return record
        }

        let history = [record(.cancelled, 3), record(.failed, nil), record(.success, nil), record(.completedWithErrors, 42), record(.success, 7)]
        XCTAssertEqual(RunRecord.expectedDirectories(from: history), 42)
        XCTAssertNil(RunRecord.expectedDirectories(from: []))
    }

    func testScanReportsFoldersAndAdvancingPosition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TwinplicEstimate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        for folder in ["a/nested", "b", "c"] {
            try FileManager.default.createDirectory(at: source.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let scans = ScanLog()
        let task = BackupTask(sourcePath: source.path, destinationPath: destination.path, excludes: [])
        let record = BackupEngine(task: task).run { progress in
            if progress.phase == .scanning { scans.add(progress) }
        }

        XCTAssertEqual(record.directoriesScanned, 5, "The source folder and the four inside it")
        let seen = scans.all
        XCTAssertEqual(seen.map(\.itemsDone), [1, 2, 3, 4, 5])
        XCTAssertEqual(seen.map(\.scanPosition), seen.map(\.scanPosition).sorted(), "Position should never move backwards")
        XCTAssertEqual(seen.first?.scanPosition, 0)
        XCTAssertLessThan(seen.last?.scanPosition ?? 1, 1)
    }
}

private final class ScanLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [RunProgress] = []

    func add(_ progress: RunProgress) { lock.withLock { items.append(progress) } }
    var all: [RunProgress] { lock.withLock { items } }
}
