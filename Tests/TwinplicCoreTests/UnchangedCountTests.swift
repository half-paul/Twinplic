import XCTest
@testable import TwinplicCore

final class UnchangedCountTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("TwinplicUnchanged-\(UUID().uuidString)")
        source = root.appendingPathComponent("source")
        destination = root.appendingPathComponent("destination")
        try fileManager.createDirectory(at: source.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for name in ["a.txt", "sub/b.txt", "sub/c.txt", "skip.log"] {
            try Data("data".utf8).write(to: source.appendingPathComponent(name))
        }
        try fileManager.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "a.txt")
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private var task: BackupTask {
        BackupTask(sourcePath: source.path, destinationPath: destination.path, excludes: ["*.log"])
    }

    /// Backs everything up, then changes one file and adds another.
    private func backUpThenChange() throws {
        XCTAssertEqual(BackupEngine(task: task).run().status, .success)
        try Data("longer data".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("new".utf8).write(to: source.appendingPathComponent("new.txt"))
    }

    func testPreviewCountsFilesAndLinksButNotFoldersOrExcludedItems() throws {
        try backUpThenChange()

        let plan = BackupEngine(task: task).preview()

        XCTAssertEqual(plan.unchangedCount, 3, "sub/b.txt, sub/c.txt and link")
        XCTAssertEqual(plan.copyCount, 1)
        XCTAssertEqual(plan.updateCount, 1)
    }

    func testDryRunRecordsTheSameCount() throws {
        try backUpThenChange()
        var dryRun = task
        dryRun.dryRun = true

        XCTAssertEqual(BackupEngine(task: dryRun).run().filesUnchanged, 3)
    }

    func testNothingIsUnchangedInAnEmptyDestination() {
        XCTAssertEqual(BackupEngine(task: task).preview().unchangedCount, 0)
    }

    func testChangedLinkTargetIsNotCounted() throws {
        XCTAssertEqual(BackupEngine(task: task).run().status, .success)
        let link = source.appendingPathComponent("link").path
        try fileManager.removeItem(atPath: link)
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: "sub/b.txt")

        let plan = BackupEngine(task: task).preview()

        XCTAssertEqual(plan.unchangedCount, 3, "a.txt, sub/b.txt and sub/c.txt")
        XCTAssertEqual(plan.updateCount, 1)
    }

    func testStoppedRunHasNoCount() {
        var dryRun = task
        dryRun.dryRun = true
        let engine = BackupEngine(task: dryRun)
        engine.cancel()

        XCTAssertNil(engine.run().filesUnchanged)
    }
}
