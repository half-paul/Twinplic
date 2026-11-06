import Darwin
import Foundation

public enum PreflightError: LocalizedError, Equatable {
    case sourceMissing(String)
    case destinationMissing(String)
    case volumeNotMounted(String)
    case sameFolder
    case nestedFolders
    case emptySource
    case unrecognizedDestination(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            "The source folder doesn't exist: \(path)"
        case .destinationMissing(let path):
            "The destination folder doesn't exist: \(path)"
        case .volumeNotMounted(let path):
            "The disk for \(path) isn't connected."
        case .sameFolder:
            "The source and destination are the same folder."
        case .nestedFolders:
            "The source and destination can't be inside each other."
        case .emptySource:
            "The source is empty but the destination has files. Nothing was changed, because mirroring would remove everything."
        case .unrecognizedDestination(let path):
            "\(path) already has files that Twinplic didn't put there. This backup could replace or remove them."
        }
    }
}

enum Preflight {
    /// Throws if running `task` could damage data. `allowUnrecognizedDestination` is the
    /// user's explicit consent to take over a non-empty folder without a Twinplic marker.
    static func check(_ task: BackupTask, allowUnrecognizedDestination: Bool) throws {
        let source = try existingFolder(task.sourcePath, missing: PreflightError.sourceMissing(task.sourcePath))
        let destination = try existingFolder(task.destinationPath, missing: PreflightError.destinationMissing(task.destinationPath))

        if source == destination { throw PreflightError.sameFolder }
        if isInside(source, destination) || isInside(destination, source) {
            throw PreflightError.nestedFolders
        }

        let destinationItems = try visibleItems(in: task.destinationPath, excludes: task.excludes)

        // An unplugged or wiped source looks like "everything was deleted".
        if task.deleteExtras, !destinationItems.isEmpty {
            let sourceItems = try visibleItems(in: task.sourcePath, excludes: task.excludes)
            if sourceItems.isEmpty { throw PreflightError.emptySource }
        }

        let canDestroy = task.deleteExtras || !task.safetyNetEnabled
        let hasMarker = FileManager.default.fileExists(atPath: joinPath(task.destinationPath, Reserved.markerFile))
        if canDestroy, !destinationItems.isEmpty, !hasMarker, !allowUnrecognizedDestination {
            throw PreflightError.unrecognizedDestination(task.destinationPath)
        }
    }

    private static func existingFolder(_ path: String, missing: PreflightError) throws -> String {
        var isDirectory: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            if let volume = volumeRoot(of: path), !isMounted(volume) {
                throw PreflightError.volumeNotMounted(path)
            }
            throw missing
        }

        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        // /Volumes/Name can survive as a plain folder on the startup disk after an
        // unclean eject. Writing there would fill the startup disk, not the backup.
        if let volume = volumeRoot(of: resolved), !isMounted(volume) {
            throw PreflightError.volumeNotMounted(path)
        }
        return resolved
    }

    static func volumeRoot(of path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return "/Volumes/\(parts[1])"
    }

    private static func isMounted(_ volume: String) -> Bool {
        var info = statfs()
        guard statfs(volume, &info) == 0 else { return false }
        let mountPoint = withUnsafeBytes(of: &info.f_mntonname) { bytes in
            String(cString: bytes.bindMemory(to: CChar.self).baseAddress!)
        }
        return mountPoint == volume
    }

    private static func isInside(_ path: String, _ parent: String) -> Bool {
        path.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }

    private static func visibleItems(in path: String, excludes: [String]) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path).filter { name in
            if name == Reserved.safetyNetFolder || name == Reserved.markerFile { return false }
            if name.hasPrefix(Reserved.tempPrefix) { return false }
            return !excludes.contains { fnmatch($0, name, 0) == 0 }
        }
    }
}
