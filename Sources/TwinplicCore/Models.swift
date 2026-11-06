import Foundation

/// Names the engine owns on a destination. These are never copied or treated as extras.
public enum Reserved {
    public static let safetyNetFolder = "_Twinplic_SafetyNet"
    public static let markerFile = ".twinplic-destination"
    public static let tempPrefix = ".twinplic-tmp-"
}

public struct BackupTask: Codable, Identifiable, Hashable, Sendable {
    public static let defaultExcludes = [
        ".DS_Store", ".Trashes", ".Spotlight-V100", ".fseventsd",
        ".DocumentRevisions-V100", ".TemporaryItems", ".VolumeIcon.icns",
    ]

    public var id: UUID
    public var name: String
    public var sourcePath: String
    public var destinationPath: String
    /// Mirror mode: remove destination items that no longer exist on the source.
    public var deleteExtras: Bool
    public var safetyNetEnabled: Bool
    public var safetyNetRetentionDays: Int
    public var verifyCopies: Bool
    /// `fnmatch` globs, tested against both the item name and its relative path.
    public var excludes: [String]
    public var schedule: Schedule
    /// Scheduled runs are skipped while the Mac is on battery. Manual runs aren't affected.
    public var skipOnBattery: Bool
    /// Every run, manual or scheduled, reports what it would change and writes nothing.
    public var dryRun: Bool

    public init(
        id: UUID = UUID(),
        name: String = "New Backup",
        sourcePath: String = "",
        destinationPath: String = "",
        deleteExtras: Bool = true,
        safetyNetEnabled: Bool = true,
        safetyNetRetentionDays: Int = 30,
        verifyCopies: Bool = false,
        excludes: [String] = BackupTask.defaultExcludes,
        schedule: Schedule = .manual,
        skipOnBattery: Bool = false,
        dryRun: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.deleteExtras = deleteExtras
        self.safetyNetEnabled = safetyNetEnabled
        self.safetyNetRetentionDays = safetyNetRetentionDays
        self.verifyCopies = verifyCopies
        self.excludes = excludes
        self.schedule = schedule
        self.skipOnBattery = skipOnBattery
        self.dryRun = dryRun
    }

    /// Written by hand so tasks saved before `skipOnBattery` and `dryRun` existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        destinationPath = try container.decode(String.self, forKey: .destinationPath)
        deleteExtras = try container.decode(Bool.self, forKey: .deleteExtras)
        safetyNetEnabled = try container.decode(Bool.self, forKey: .safetyNetEnabled)
        safetyNetRetentionDays = try container.decode(Int.self, forKey: .safetyNetRetentionDays)
        verifyCopies = try container.decode(Bool.self, forKey: .verifyCopies)
        excludes = try container.decode([String].self, forKey: .excludes)
        schedule = try container.decode(Schedule.self, forKey: .schedule)
        skipOnBattery = try container.decodeIfPresent(Bool.self, forKey: .skipOnBattery) ?? false
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
    }
}

public enum ItemKind: String, Codable, Sendable {
    case file, directory, symlink
}

public struct PlanItem: Hashable, Sendable, Identifiable {
    public enum Action: String, Sendable {
        case copyNew, update, delete
    }

    public var action: Action
    public var relativePath: String
    public var kind: ItemKind
    public var size: Int64
    /// Files this item stands for. A deleted folder counts everything inside it, and
    /// folders being created or leftover temporary files count as zero.
    public var fileCount = 1

    public var id: String { "\(action.rawValue):\(relativePath)" }
}

public struct BackupPlan: Sendable {
    public var items: [PlanItem] = []
    /// Problems found while scanning. Affected subtrees are skipped, never deleted.
    public var errors: [String] = []
    public var skippedSpecialFiles = 0
    public var directoriesScanned = 0
    /// Files and symlinks that already match, by the same test that decides what to copy.
    public var unchangedCount = 0
    public var access = AccessProblems()

    public init() {}

    public var bytesToCopy: Int64 {
        items.lazy.filter { $0.action != .delete && $0.kind == .file }.reduce(0) { $0 + $1.size }
    }
    public var copyCount: Int { fileCount(.copyNew) }
    public var updateCount: Int { fileCount(.update) }
    public var deleteCount: Int { fileCount(.delete) }
    public var isEmpty: Bool { items.isEmpty }

    private func fileCount(_ action: PlanItem.Action) -> Int {
        items.lazy.filter { $0.action == action }.reduce(0) { $0 + $1.fileCount }
    }
}

public struct RunProgress: Sendable {
    public enum Phase: String, Sendable {
        case scanning = "Scanning"
        case simulating = "Checking changes"
        case removing = "Removing extras"
        case copying = "Copying"
        case verifying = "Verifying"
        case finishing = "Finishing"
    }

    public var phase: Phase
    public var currentPath: String
    public var itemsDone: Int
    public var itemsTotal: Int
    public var bytesDone: Int64
    public var bytesTotal: Int64
    /// How far through the folder tree a scan is, from 0 to 1. Each folder splits its
    /// parent's share evenly, so this is rough, but it needs no earlier run.
    public var scanPosition = 0.0

    /// Totals aren't known until scanning finishes, so `itemsDone` counts folders visited.
    public static func scanning(_ path: String, directoriesDone: Int, position: Double) -> RunProgress {
        RunProgress(
            phase: .scanning, currentPath: path, itemsDone: directoriesDone, itemsTotal: 0,
            bytesDone: 0, bytesTotal: 0, scanPosition: position
        )
    }

    public var fraction: Double {
        if bytesTotal > 0 { return min(1, Double(bytesDone) / Double(bytesTotal)) }
        return itemsTotal > 0 ? min(1, Double(itemsDone) / Double(itemsTotal)) : 0
    }
}

public struct RunRecord: Codable, Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case success, completedWithErrors, cancelled, failed, skipped
    }

    public static let maxStoredErrors = 200
    public static let maxStoredPlannedChanges = 200

    public var id = UUID()
    public var taskID: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var status: Status
    public var itemsCopied = 0
    public var itemsDeleted = 0
    // Optional because records saved by earlier versions don't have them.
    public var filesAdded: Int? = 0
    public var filesReplaced: Int? = 0
    public var filesDeleted: Int? = 0
    public var bytesCopied: Int64 = 0
    public var errors: [String] = []
    public var errorCount = 0
    // Optional because records saved by earlier versions don't have them.
    public var isDryRun: Bool?
    /// What a dry run would have done, one line per item, capped at `maxStoredPlannedChanges`.
    public var plannedChanges: [String]?
    /// Lets the next run estimate its scan. Optional for the same reason as above.
    public var directoriesScanned: Int?
    /// Optional for the same reason, and also nil for a stopped run.
    public var filesUnchanged: Int?
    /// Nil if nothing was refused, which is also what records from earlier versions read as.
    public var access: AccessProblems?

    public init(taskID: UUID, startedAt: Date, finishedAt: Date, status: Status) {
        self.taskID = taskID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
    }

    mutating func addError(_ message: String) {
        errorCount += 1
        if errors.count < Self.maxStoredErrors { errors.append(message) }
    }

    mutating func noteAccess(_ error: Error) {
        var problems = access ?? AccessProblems()
        problems.note(error)
        if !problems.isEmpty { access = problems }
    }

    mutating func addPlannedChange(_ line: String) {
        var lines = plannedChanges ?? []
        if lines.count < Self.maxStoredPlannedChanges { lines.append(line) }
        plannedChanges = lines
    }
}
