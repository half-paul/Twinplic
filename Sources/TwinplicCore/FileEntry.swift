import Darwin
import Foundation

/// The result of `lstat` on one path. Symlinks are described, never followed.
struct FileEntry {
    enum Kind { case file, directory, symlink, special }

    var kind: Kind
    var size: Int64
    var modified: Double

    static func read(_ path: String) -> FileEntry? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }

        let kind: Kind
        switch info.st_mode & S_IFMT {
        case S_IFREG: kind = .file
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symlink
        default: kind = .special
        }
        let time = info.st_mtimespec
        return FileEntry(
            kind: kind,
            size: Int64(info.st_size),
            modified: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
        )
    }

    /// Lists a folder with each item's details fetched alongside its name. On a network
    /// disk this avoids one round trip per file, which is what makes `read` slow there.
    static func list(_ path: String) throws -> DirectoryListing {
        let keys: [URLResourceKey] = [.fileResourceTypeKey, .fileSizeKey, .contentModificationDateKey]
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)

        var listing = DirectoryListing()
        listing.names.reserveCapacity(children.count)
        for child in children {
            let name = child.lastPathComponent
            listing.names.append(name)
            if let values = try? child.resourceValues(forKeys: Set(keys)), let entry = FileEntry(values) {
                listing.entries[name] = entry
            }
        }
        listing.names.sort()
        return listing
    }

    var itemKind: ItemKind? {
        switch kind {
        case .file: .file
        case .directory: .directory
        case .symlink: .symlink
        case .special: nil
        }
    }
}

// In an extension, so the struct keeps its memberwise initializer.
extension FileEntry {
    /// Nil if the listing left out anything needed, so the caller falls back to `read`.
    private init?(_ values: URLResourceValues) {
        guard let type = values.fileResourceType, let date = values.contentModificationDate else { return nil }
        switch type {
        case .regular: kind = .file
        case .directory: kind = .directory
        case .symbolicLink: kind = .symlink
        default: kind = .special
        }
        if kind == .file, values.fileSize == nil { return nil }
        size = Int64(values.fileSize ?? 0)
        modified = date.timeIntervalSince1970
    }
}

/// One folder's contents. `names` is complete and sorted. `entries` can miss a name whose
/// details weren't available, and that item must still be treated as present.
struct DirectoryListing {
    var names: [String] = []
    var entries: [String: FileEntry] = [:]
}

func errnoMessage(_ code: Int32 = errno) -> String {
    String(cString: strerror(code))
}

func joinPath(_ base: String, _ relative: String) -> String {
    if relative.isEmpty { return base }
    if base.isEmpty { return relative }
    return base.hasSuffix("/") ? base + relative : base + "/" + relative
}
