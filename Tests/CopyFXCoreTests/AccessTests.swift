import Darwin
import XCTest
@testable import CopyFXCore

final class AccessTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("CopyFXAccess-\(UUID().uuidString)")
        source = root.appendingPathComponent("source")
        destination = root.appendingPathComponent("destination")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for path in locked { chmod(path, 0o755) }
        try? fileManager.removeItem(at: root)
    }

    private var locked: [String] = []

    private func lock(_ url: URL) {
        locked.append(url.path)
        XCTAssertEqual(chmod(url.path, 0o000), 0)
    }

    private var task: BackupTask {
        BackupTask(sourcePath: source.path, destinationPath: destination.path, excludes: [])
    }

    func testPrivacyBlockAndFilePermissionsAreToldApart() {
        var problems = AccessProblems()
        problems.note(code: EPERM)
        problems.note(code: EACCES)
        problems.note(code: EACCES)
        problems.note(code: ENOENT)

        XCTAssertEqual(problems.privacyBlocked, 1)
        XCTAssertEqual(problems.noPermission, 2)
    }

    func testCauseIsFoundInsideFoundationErrors() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        let wrapped = NSError(
            domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue,
            userInfo: [NSUnderlyingErrorKey: posix]
        )
        XCTAssertEqual(AccessProblems.posixCode(of: wrapped), EPERM)
        XCTAssertEqual(AccessProblems.posixCode(of: CopyError.posix(EACCES)), EACCES)
        XCTAssertEqual(AccessProblems.posixCode(of: NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue)), EACCES)
        XCTAssertNil(AccessProblems.posixCode(of: CopyError.verificationFailed))
        XCTAssertTrue(AccessProblems(CopyError.verificationFailed).isEmpty)
    }

    func testUnreadableFolderIsCountedAndItsBackupKept() throws {
        let folder = source.appendingPathComponent("private")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: folder.appendingPathComponent("a.txt"))
        XCTAssertEqual(BackupEngine(task: task).run().status, .success)

        lock(folder)
        let record = BackupEngine(task: task).run()

        XCTAssertEqual(record.status, .completedWithErrors)
        XCTAssertEqual(record.access?.noPermission, 1)
        XCTAssertEqual(record.access?.privacyBlocked, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("private/a.txt").path))
    }

    func testUnreadableFileIsCounted() throws {
        let file = source.appendingPathComponent("secret.txt")
        try Data("data".utf8).write(to: file)
        lock(file)

        let record = BackupEngine(task: task).run()

        XCTAssertEqual(record.status, .completedWithErrors)
        XCTAssertEqual(record.access?.noPermission, 1)
    }

    func testCleanRunRecordsNoProblems() throws {
        try Data("data".utf8).write(to: source.appendingPathComponent("a.txt"))
        XCTAssertNil(BackupEngine(task: task).run().access)
    }

    func testOlderRecordsStillLoad() throws {
        let store = TaskStore(directory: root.appendingPathComponent("store"))
        var record = RunRecord(taskID: UUID(), startedAt: Date(), finishedAt: Date(), status: .success)
        record.access = nil
        try store.append(record)
        XCTAssertNil(try store.loadHistory(for: record.taskID).first?.access)
    }

    func testFullDiskAccessCheck() throws {
        let readable = root.appendingPathComponent("readable")
        let refused = root.appendingPathComponent("refused")
        try Data().write(to: readable)
        try Data().write(to: refused)
        lock(refused)
        let missing = root.appendingPathComponent("missing").path

        XCTAssertEqual(FullDiskAccess.check([missing, readable.path]), true)
        XCTAssertEqual(FullDiskAccess.check([refused.path, readable.path]), true)
        XCTAssertEqual(FullDiskAccess.check([refused.path, missing]), false)
        XCTAssertNil(FullDiskAccess.check([missing]))
    }
}
