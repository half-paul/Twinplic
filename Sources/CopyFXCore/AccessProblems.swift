import Darwin
import Foundation

/// Counts items a run was refused, split by what could fix them.
public struct AccessProblems: Codable, Hashable, Sendable {
    /// `EPERM`: usually macOS privacy protection, which Full Disk Access lifts. It can also
    /// be a locked file, so only treat it as a privacy block if the app lacks that access.
    public var privacyBlocked = 0
    /// `EACCES`: the item's own permissions, which Full Disk Access doesn't change.
    public var noPermission = 0

    public init() {}

    public init(_ error: Error) {
        note(error)
    }

    public var isEmpty: Bool { privacyBlocked == 0 && noPermission == 0 }

    mutating func note(code: Int32) {
        switch code {
        case EPERM: privacyBlocked += 1
        case EACCES: noPermission += 1
        default: break
        }
    }

    mutating func note(_ error: Error) {
        if let code = Self.posixCode(of: error) { note(code: code) }
    }

    /// Foundation wraps the system error, so the real cause can be a few levels down.
    static func posixCode(of error: Error) -> Int32? {
        if case CopyError.posix(let code) = error { return code }

        let wrapped = error as NSError
        if wrapped.domain == NSPOSIXErrorDomain { return Int32(wrapped.code) }
        if let underlying = wrapped.userInfo[NSUnderlyingErrorKey] as? Error,
           let code = posixCode(of: underlying) {
            return code
        }
        if wrapped.domain == NSCocoaErrorDomain,
           wrapped.code == CocoaError.fileReadNoPermission.rawValue
            || wrapped.code == CocoaError.fileWriteNoPermission.rawValue {
            return EACCES
        }
        return nil
    }
}

/// macOS has no API for this and can't be asked to grant it, so the only test is to try
/// opening files that nothing else can reach. Only the user can turn it on, in System Settings.
public enum FullDiskAccess {
    private static let protectedFiles = [
        "Library/Application Support/com.apple.TCC/TCC.db",
        "Library/Safari/Bookmarks.plist",
        "Library/Safari/CloudTabs.db",
    ]

    /// Nil if none of the files exist, so there's nothing to judge by.
    public static var isGranted: Bool? {
        check(protectedFiles.map { joinPath(NSHomeDirectory(), $0) })
    }

    static func check(_ paths: [String]) -> Bool? {
        var refused = false
        for path in paths {
            let descriptor = open(path, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return true
            }
            if errno == EPERM || errno == EACCES { refused = true }
        }
        return refused ? false : nil
    }
}
