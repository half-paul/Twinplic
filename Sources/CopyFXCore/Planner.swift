import Darwin
import Foundation

/// Compares source and destination and lists what a run would change. Writes nothing.
struct Planner {
    /// exFAT stores modification times at 2 second resolution.
    static let timestampTolerance = 2.0

    let task: BackupTask
    let isCancelled: @Sendable () -> Bool
    let onScan: @Sendable (RunProgress) -> Void

    /// The part of the whole tree that a folder stands for.
    private struct TreeShare {
        var start = 0.0
        var width = 1.0
    }

    func makePlan() -> BackupPlan {
        var plan = BackupPlan()
        walk("", destinationExists: true, share: TreeShare(), into: &plan)
        return plan
    }

    private func walk(_ relative: String, destinationExists: Bool, share: TreeShare, into plan: inout BackupPlan) {
        if isCancelled() { return }
        plan.directoriesScanned += 1
        onScan(.scanning(relative, directoriesDone: plan.directoriesScanned, position: share.start))

        let sourceDirectory = joinPath(task.sourcePath, relative)
        let destinationDirectory = joinPath(task.destinationPath, relative)

        // A folder we cannot list is not an empty folder. Returning here keeps its
        // backup intact, because nothing below it is ever compared or deleted.
        let sourceListing: DirectoryListing
        do {
            sourceListing = try FileEntry.list(sourceDirectory)
        } catch {
            plan.errors.append("Could not read \(sourceDirectory): \(error.localizedDescription)")
            plan.access.note(error)
            return
        }

        var destinationListing = DirectoryListing()
        if destinationExists {
            do {
                destinationListing = try FileEntry.list(destinationDirectory)
            } catch {
                plan.errors.append("Could not read \(destinationDirectory): \(error.localizedDescription)")
                plan.access.note(error)
                return
            }
        }

        let childWidth = share.width / Double(max(sourceListing.names.count, 1))
        for (index, name) in sourceListing.names.enumerated() {
            if isCancelled() { return }
            let childShare = TreeShare(start: share.start + childWidth * Double(index), width: childWidth)
            let itemPath = joinPath(relative, name)
            if isIgnored(name: name, relative: itemPath, parent: relative) { continue }

            let sourcePath = joinPath(sourceDirectory, name)
            guard let source = sourceListing.entries[name] ?? FileEntry.read(sourcePath) else {
                let code = errno
                plan.errors.append("Could not read \(sourcePath): \(errnoMessage(code))")
                plan.access.note(code: code)
                continue
            }
            guard let kind = source.itemKind else {
                plan.skippedSpecialFiles += 1
                continue
            }

            // A name missing from the listing can still exist here as `foo` for `Foo`,
            // on a case or normalization insensitive volume, so only the disk can say.
            let destination = destinationExists
                ? destinationListing.entries[name] ?? FileEntry.read(joinPath(destinationDirectory, name))
                : nil
            compare(source, kind: kind, destination, relative: itemPath, share: childShare, into: &plan)
        }

        removeLeftovers(destinationListing, sourceNames: sourceListing.names, parent: relative, into: &plan)
    }

    private func compare(
        _ source: FileEntry, kind: ItemKind, _ destination: FileEntry?,
        relative: String, share: TreeShare, into plan: inout BackupPlan
    ) {
        let size = kind == .file ? source.size : 0

        let fileCount = kind == .directory ? 0 : 1

        guard let destination else {
            plan.items.append(PlanItem(action: .copyNew, relativePath: relative, kind: kind, size: size, fileCount: fileCount))
            if kind == .directory { walk(relative, destinationExists: false, share: share, into: &plan) }
            return
        }

        if destination.kind != source.kind {
            // A file and a symlink can swap in one rename, so that's a replacement.
            if kind != .directory, destination.kind != .directory {
                plan.items.append(PlanItem(action: .update, relativePath: relative, kind: kind, size: size))
                return
            }
            // A folder is involved, so the old item has to go even in additive mode.
            plan.items.append(deletion(of: relative, entry: destination))
            plan.items.append(PlanItem(action: .copyNew, relativePath: relative, kind: kind, size: size, fileCount: fileCount))
            if kind == .directory { walk(relative, destinationExists: false, share: share, into: &plan) }
            return
        }

        switch kind {
        case .directory:
            walk(relative, destinationExists: true, share: share, into: &plan)
        case .file:
            let sameSize = source.size == destination.size
            let sameTime = abs(source.modified - destination.modified) < Self.timestampTolerance
            if !sameSize || !sameTime {
                plan.items.append(PlanItem(action: .update, relativePath: relative, kind: .file, size: size))
            } else {
                plan.unchangedCount += 1
            }
        case .symlink:
            let fileManager = FileManager.default
            let sourceTarget = try? fileManager.destinationOfSymbolicLink(atPath: joinPath(task.sourcePath, relative))
            let destinationTarget = try? fileManager.destinationOfSymbolicLink(atPath: joinPath(task.destinationPath, relative))
            if sourceTarget != destinationTarget {
                plan.items.append(PlanItem(action: .update, relativePath: relative, kind: .symlink, size: 0))
            } else {
                plan.unchangedCount += 1
            }
        }
    }

    private func removeLeftovers(
        _ destination: DirectoryListing, sourceNames: [String], parent: String, into plan: inout BackupPlan
    ) {
        // Destination volumes can be case or normalization insensitive, so `Foo` on the
        // source may already match `foo` here. Unresolved cases are kept, not deleted.
        let sourceKeys = Set(sourceNames.map(Self.matchKey))
        let destinationDirectory = joinPath(task.destinationPath, parent)

        for name in destination.names {
            let itemPath = joinPath(parent, name)
            let entryPath = joinPath(destinationDirectory, name)

            if name.hasPrefix(Reserved.tempPrefix) {
                // Left behind by an interrupted run.
                let entry = destination.entries[name] ?? FileEntry.read(entryPath)
                plan.items.append(PlanItem(action: .delete, relativePath: itemPath, kind: entry?.itemKind ?? .file, size: entry?.size ?? 0, fileCount: 0))
                continue
            }
            guard task.deleteExtras else { continue }
            if isIgnored(name: name, relative: itemPath, parent: parent) { continue }
            if sourceKeys.contains(Self.matchKey(name)) { continue }

            guard let entry = destination.entries[name] ?? FileEntry.read(entryPath) else {
                let code = errno
                plan.errors.append("Could not read \(entryPath): \(errnoMessage(code))")
                plan.access.note(code: code)
                continue
            }
            plan.items.append(deletion(of: itemPath, entry: entry))
        }
    }

    /// A folder is removed as one item, so its contents are counted here for the log.
    private func deletion(of relative: String, entry: FileEntry) -> PlanItem {
        guard entry.kind == .directory else {
            return PlanItem(action: .delete, relativePath: relative, kind: entry.itemKind ?? .file, size: entry.size)
        }

        var files = 0
        var bytes: Int64 = 0
        tally(joinPath(task.destinationPath, relative), files: &files, bytes: &bytes)
        return PlanItem(action: .delete, relativePath: relative, kind: .directory, size: bytes, fileCount: files)
    }

    private func tally(_ path: String, files: inout Int, bytes: inout Int64) {
        guard !isCancelled(), let listing = try? FileEntry.list(path) else { return }
        for name in listing.names {
            let childPath = joinPath(path, name)
            guard let item = listing.entries[name] ?? FileEntry.read(childPath) else { continue }
            if item.kind == .directory {
                tally(childPath, files: &files, bytes: &bytes)
            } else {
                files += 1
                bytes += item.size
            }
        }
    }

    private func isIgnored(name: String, relative: String, parent: String) -> Bool {
        if name.hasPrefix(Reserved.tempPrefix) { return true }
        if parent.isEmpty, name == Reserved.safetyNetFolder || name == Reserved.markerFile { return true }
        return task.excludes.contains { pattern in
            fnmatch(pattern, name, 0) == 0 || fnmatch(pattern, relative, 0) == 0
        }
    }

    static func matchKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }
}
