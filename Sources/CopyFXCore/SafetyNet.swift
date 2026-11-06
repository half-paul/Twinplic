import Foundation

/// Holds replaced and deleted items in a dated folder on the destination.
struct SafetyNet {
    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    let destinationPath: String
    let runFolder: String

    init(destinationPath: String, date: Date = Date()) {
        self.destinationPath = destinationPath
        self.runFolder = joinPath(
            joinPath(destinationPath, Reserved.safetyNetFolder),
            Self.formatter().string(from: date)
        )
    }

    /// Both paths are on the destination volume, so this is a rename and copies no data.
    func preserve(relativePath: String) throws {
        let target = joinPath(runFolder, relativePath)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            atPath: (target as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(atPath: joinPath(destinationPath, relativePath), toPath: target)
    }

    /// Only folders whose names parse as run dates are touched.
    static func prune(destinationPath: String, retentionDays: Int, now: Date = Date()) throws {
        let root = joinPath(destinationPath, Reserved.safetyNetFolder)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root) else { return }

        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let parser = formatter()
        for name in try fileManager.contentsOfDirectory(atPath: root) {
            guard let date = parser.date(from: name), date < cutoff else { continue }
            try fileManager.removeItem(atPath: joinPath(root, name))
        }
    }
}
