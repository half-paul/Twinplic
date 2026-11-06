import Darwin
import XCTest
@testable import TwinplicCore

final class BackupEngineTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("TwinplicTests-\(UUID().uuidString)")
        source = root.appendingPathComponent("source")
        destination = root.appendingPathComponent("destination")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions changed by tests so the folder can be removed.
        chmod(source.appendingPathComponent("locked").path, 0o755)
        try? fileManager.removeItem(at: root)
    }

    private func makeTask(
        deleteExtras: Bool = true, safetyNet: Bool = true, verify: Bool = false, excludes: [String] = []
    ) -> BackupTask {
        BackupTask(
            sourcePath: source.path, destinationPath: destination.path, deleteExtras: deleteExtras,
            safetyNetEnabled: safetyNet, verifyCopies: verify, excludes: excludes
        )
    }

    @discardableResult
    private func write(_ text: String, _ path: String, in base: URL) throws -> URL {
        let url = base.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func read(_ path: String, in base: URL) throws -> String {
        String(decoding: try Data(contentsOf: base.appendingPathComponent(path)), as: UTF8.self)
    }

    private func exists(_ path: String, in base: URL) -> Bool {
        fileManager.fileExists(atPath: base.appendingPathComponent(path).path)
    }

    private func safetyNetCopies(of path: String) throws -> [String] {
        let net = destination.appendingPathComponent(Reserved.safetyNetFolder)
        guard fileManager.fileExists(atPath: net.path) else { return [] }
        return try fileManager.contentsOfDirectory(atPath: net.path).compactMap { run in
            let candidate = net.appendingPathComponent(run).appendingPathComponent(path)
            return fileManager.fileExists(atPath: candidate.path) ? try read(path, in: net.appendingPathComponent(run)) : nil
        }
    }

    // MARK: Copying

    func testCopiesTreeOnFirstRun() throws {
        try write("one", "a.txt", in: source)
        try write("two", "folder/nested/b.txt", in: source)

        let record = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(try read("a.txt", in: destination), "one")
        XCTAssertEqual(try read("folder/nested/b.txt", in: destination), "two")
    }

    func testSecondRunChangesNothing() throws {
        try write("one", "folder/a.txt", in: source)
        _ = BackupEngine(task: makeTask()).run()

        let plan = BackupEngine(task: makeTask()).preview()

        XCTAssertTrue(plan.isEmpty, "\(plan.items)")
    }

    func testPreservesTimestampsPermissionsAndXattrs() throws {
        let file = try write("data", "folder/a.txt", in: source)
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        try fileManager.setAttributes([.modificationDate: date, .posixPermissions: 0o640], ofItemAtPath: file.path)
        XCTAssertEqual(setxattr(file.path, "com.twinplic.test", "value", 5, 0, 0), 0)
        let folderDate = Date(timeIntervalSince1970: 1_100_000_000)
        try fileManager.setAttributes([.modificationDate: folderDate], ofItemAtPath: source.appendingPathComponent("folder").path)

        let record = BackupEngine(task: makeTask()).run()
        XCTAssertEqual(record.status, .success, record.errors.joined())

        let copy = destination.appendingPathComponent("folder/a.txt").path
        let attributes = try fileManager.attributesOfItem(atPath: copy)
        XCTAssertEqual(attributes[.modificationDate] as? Date, date)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        XCTAssertEqual(getxattr(copy, "com.twinplic.test", nil, 0, 0, 0), 5)

        let folder = try fileManager.attributesOfItem(atPath: destination.appendingPathComponent("folder").path)
        XCTAssertEqual(folder[.modificationDate] as? Date, folderDate)
    }

    func testCopiesSymlinkWithoutFollowingIt() throws {
        try write("outside", "target.txt", in: root)
        try fileManager.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "../target.txt")

        let record = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("link").path), "../target.txt")
    }

    func testUpdatesChangedSymlink() throws {
        let link = source.appendingPathComponent("link").path
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: "old")
        _ = BackupEngine(task: makeTask(safetyNet: false)).run()
        try fileManager.removeItem(atPath: link)
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: "new")

        let record = BackupEngine(task: makeTask(safetyNet: false)).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("link").path), "new")
    }

    func testVerifiedCopySucceeds() throws {
        try write(String(repeating: "x", count: 100_000), "big.bin", in: source)

        let record = BackupEngine(task: makeTask(verify: true)).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(record.bytesCopied, 100_000)
    }

    func testLeavesNoTemporaryFiles() throws {
        try write("one", "folder/a.txt", in: source)
        _ = BackupEngine(task: makeTask()).run()

        let names = fileManager.enumerator(atPath: destination.path)?.allObjects as? [String] ?? []

        XCTAssertFalse(names.contains { $0.contains(Reserved.tempPrefix) }, "\(names)")
    }

    func testRemovesStaleTemporaryFileWithoutSavingIt() throws {
        try write("one", "a.txt", in: source)
        _ = BackupEngine(task: makeTask()).run()
        let stale = Reserved.tempPrefix + "stale"
        try write("partial", stale, in: destination)

        _ = BackupEngine(task: makeTask()).run()

        XCTAssertFalse(exists(stale, in: destination))
        XCTAssertEqual(try safetyNetCopies(of: stale), [])
    }

    // MARK: Mirroring and SafetyNet

    func testMirrorMovesExtrasToSafetyNet() throws {
        try write("keep", "keep.txt", in: source)
        let removed = try write("gone", "gone.txt", in: source)
        _ = BackupEngine(task: makeTask()).run()
        try fileManager.removeItem(at: removed)

        let record = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(record.itemsDeleted, 1)
        XCTAssertFalse(exists("gone.txt", in: destination))
        XCTAssertEqual(try safetyNetCopies(of: "gone.txt"), ["gone"])
    }

    func testUpdatedFileKeepsOldVersionInSafetyNet() throws {
        try write("version one", "a.txt", in: source)
        _ = BackupEngine(task: makeTask()).run()
        try write("version two!", "a.txt", in: source)

        _ = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(try read("a.txt", in: destination), "version two!")
        XCTAssertEqual(try safetyNetCopies(of: "a.txt"), ["version one"])
    }

    func testAdditiveModeKeepsExtras() throws {
        try write("new", "a.txt", in: source)
        try write("mine", "extra.txt", in: destination)

        let record = BackupEngine(task: makeTask(deleteExtras: false)).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(try read("extra.txt", in: destination), "mine")
    }

    func testFileReplacedByFolder() throws {
        let item = try write("file", "item", in: source)
        _ = BackupEngine(task: makeTask()).run()
        try fileManager.removeItem(at: item)
        try write("inside", "item/child.txt", in: source)

        let record = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(try read("item/child.txt", in: destination), "inside")
        XCTAssertEqual(try safetyNetCopies(of: "item"), ["file"])
    }

    func testFolderReplacedByFile() throws {
        try write("inside", "item/child.txt", in: source)
        _ = BackupEngine(task: makeTask()).run()
        try fileManager.removeItem(at: source.appendingPathComponent("item"))
        try write("file", "item", in: source)

        let record = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(try read("item", in: destination), "file")
        XCTAssertEqual(try safetyNetCopies(of: "item/child.txt"), ["inside"])
    }

    func testCaseOnlyDifferenceIsNotDeleted() throws {
        try write("same", "Foo.txt", in: source)
        try write("marker", Reserved.markerFile, in: destination)
        try write("same", "foo.txt", in: destination)

        _ = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(try read("Foo.txt", in: destination), "same")
    }

    func testPruneRemovesOnlyExpiredRunFolders() throws {
        let net = destination.appendingPathComponent(Reserved.safetyNetFolder)
        try write("old", "2000-01-01_00-00-00/a.txt", in: net)
        try write("recent", "2030-03-10_00-00-00/a.txt", in: net)
        try write("user", "not-a-run/a.txt", in: net)

        try SafetyNet.prune(destinationPath: destination.path, retentionDays: 30, now: Date(timeIntervalSince1970: 1_900_000_000))

        XCTAssertFalse(exists("2000-01-01_00-00-00", in: net))
        XCTAssertTrue(exists("2030-03-10_00-00-00", in: net))
        XCTAssertTrue(exists("not-a-run", in: net))
    }

    // MARK: Excludes

    func testExcludedItemsAreNotCopiedAndNotDeleted() throws {
        try write("copied", "a.txt", in: source)
        try write("skipped", "cache/b.tmp", in: source)
        try write("marker", Reserved.markerFile, in: destination)
        try write("protected", "cache/old.tmp", in: destination)

        let record = BackupEngine(task: makeTask(excludes: ["cache"])).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertFalse(exists("cache/b.tmp", in: destination))
        XCTAssertEqual(try read("cache/old.tmp", in: destination), "protected")
    }

    // MARK: Data protection

    func testUnreadableSourceFolderKeepsItsBackup() throws {
        try write("precious", "locked/data.txt", in: source)
        try write("other", "a.txt", in: source)
        _ = BackupEngine(task: makeTask()).run()
        XCTAssertEqual(chmod(source.appendingPathComponent("locked").path, 0o000), 0)

        let record = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(record.status, .completedWithErrors)
        XCTAssertEqual(record.itemsDeleted, 0)
        XCTAssertEqual(try read("locked/data.txt", in: destination), "precious")
    }

    func testPreviewWritesNothing() throws {
        try write("one", "a.txt", in: source)

        let plan = BackupEngine(task: makeTask()).preview()

        XCTAssertEqual(plan.copyCount, 1)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: destination.path), [])
    }

    func testDryRunCountsChangesAndWritesNothing() throws {
        try write("new", "added.txt", in: source)
        try write("changed", "same.txt", in: source)
        try write("old", "same.txt", in: destination)
        try write("extra", "extra.txt", in: destination)

        var task = makeTask()
        task.dryRun = true
        let record = BackupEngine(task: task).run()

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(record.isDryRun, true)
        XCTAssertEqual(record.filesAdded, 1)
        XCTAssertEqual(record.filesReplaced, 1)
        XCTAssertEqual(record.filesDeleted, 1)
        XCTAssertEqual(record.bytesCopied, 10)
        XCTAssertEqual(
            record.plannedChanges?.sorted(),
            ["Add added.txt", "Delete extra.txt", "Replace same.txt"]
        )

        let contents = try fileManager.contentsOfDirectory(atPath: destination.path).sorted()
        XCTAssertEqual(contents, ["extra.txt", "same.txt"], "no marker, SafetyNet or copied files")
        XCTAssertEqual(try read("same.txt", in: destination), "old")
    }

    func testDryRunStillRefusesUnsafeRuns() throws {
        try write("keep", "keep.txt", in: destination)

        var task = makeTask()
        task.dryRun = true
        let record = BackupEngine(task: task).run()

        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.isDryRun, true)
        XCTAssertTrue(exists("keep.txt", in: destination))
    }

    func testRealRunIsNotMarkedDry() throws {
        try write("one", "a.txt", in: source)

        let record = BackupEngine(task: makeTask()).run()

        XCTAssertNil(record.isDryRun)
        XCTAssertNil(record.plannedChanges)
    }

    func testRefusesEmptySourceWhenDestinationHasFiles() throws {
        try write("backup", "a.txt", in: destination)
        try write("marker", Reserved.markerFile, in: destination)

        let record = BackupEngine(task: makeTask()).run(allowUnrecognizedDestination: true)

        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(try read("a.txt", in: destination), "backup")
    }

    func testRefusesUnrecognizedDestinationWithoutConsent() throws {
        try write("new", "a.txt", in: source)
        try write("unrelated", "family-photos.txt", in: destination)

        XCTAssertThrowsError(try BackupEngine(task: makeTask()).preflight()) { error in
            XCTAssertEqual(error as? PreflightError, .unrecognizedDestination(destination.path))
        }
        let record = BackupEngine(task: makeTask()).run()

        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(try read("family-photos.txt", in: destination), "unrelated")
    }

    func testConsentAllowsUnrecognizedDestination() throws {
        try write("new", "a.txt", in: source)
        try write("old", "b.txt", in: destination)

        let record = BackupEngine(task: makeTask()).run(allowUnrecognizedDestination: true)

        XCTAssertEqual(record.status, .success, record.errors.joined())
        XCTAssertEqual(try safetyNetCopies(of: "b.txt"), ["old"])
    }

    func testRefusesNestedAndIdenticalFolders() throws {
        try write("x", "a.txt", in: source)
        var task = makeTask()

        task.destinationPath = source.path
        XCTAssertThrowsError(try BackupEngine(task: task).preflight()) {
            XCTAssertEqual($0 as? PreflightError, .sameFolder)
        }

        let inner = source.appendingPathComponent("inner")
        try fileManager.createDirectory(at: inner, withIntermediateDirectories: true)
        task.destinationPath = inner.path
        XCTAssertThrowsError(try BackupEngine(task: task).preflight()) {
            XCTAssertEqual($0 as? PreflightError, .nestedFolders)
        }
    }

    func testRefusesMissingFolders() {
        var task = makeTask()
        task.sourcePath = root.appendingPathComponent("nope").path
        XCTAssertThrowsError(try BackupEngine(task: task).preflight()) {
            XCTAssertEqual($0 as? PreflightError, .sourceMissing(task.sourcePath))
        }
    }

    func testVolumeRootDetection() {
        XCTAssertEqual(Preflight.volumeRoot(of: "/Volumes/Backup/Work"), "/Volumes/Backup")
        XCTAssertEqual(Preflight.volumeRoot(of: "/Volumes/Backup"), "/Volumes/Backup")
        XCTAssertNil(Preflight.volumeRoot(of: "/Users/someone/Volumes/Backup"))
    }

    func testListingMatchesLstatForEveryKindOfItem() throws {
        try write("hello", "plain.txt", in: source)
        try write("hidden", ".hidden", in: source)
        try write("accent", "caf\u{65}\u{301}.txt", in: source)
        try write("percent", "100% done #1?.txt", in: source)
        try write("nested", "folder/child.txt", in: source)
        try fileManager.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "plain.txt")
        try fileManager.createSymbolicLink(atPath: source.appendingPathComponent("dangling").path, withDestinationPath: "missing")
        XCTAssertEqual(mkfifo(source.appendingPathComponent("pipe").path, 0o644), 0)

        let listing = try FileEntry.list(source.path)

        let expected = try fileManager.contentsOfDirectory(atPath: source.path).sorted()
        XCTAssertEqual(listing.names, expected)
        for name in expected {
            let path = joinPath(source.path, name)
            let listed = try XCTUnwrap(listing.entries[name], name)
            let read = try XCTUnwrap(FileEntry.read(path), name)
            XCTAssertEqual(listed.kind, read.kind, name)
            XCTAssertEqual(listed.modified, read.modified, accuracy: 0.001, name)
            if read.kind == .file { XCTAssertEqual(listed.size, read.size, name) }
        }
    }

    func testListingThrowsForUnreadableFolder() {
        XCTAssertThrowsError(try FileEntry.list(source.appendingPathComponent("missing").path))
    }

    func testDeletedFolderCountsNestedFiles() throws {
        try write("keep", "keep.txt", in: source)
        try write("12345", "gone/a.txt", in: destination)
        try write("123", "gone/deep/b.txt", in: destination)

        let plan = BackupEngine(task: makeTask()).preview()

        let item = try XCTUnwrap(plan.items.first { $0.action == .delete && $0.relativePath == "gone" })
        XCTAssertEqual(item.fileCount, 2)
        XCTAssertEqual(item.size, 8)
    }

    func testCancelledRunStopsBeforeCopying() throws {
        try write("one", "a.txt", in: source)
        let engine = BackupEngine(task: makeTask())
        engine.cancel()

        let record = engine.run()

        XCTAssertEqual(record.status, .cancelled)
        XCTAssertFalse(exists("a.txt", in: destination))
    }
}
