import Darwin
import Foundation

/// Schedules tasks with launchd, so they run while the app is closed and catch up after sleep.
public struct LaunchAgentScheduler: Sendable {
    public static let labelPrefix = "com.twinplic.task."
    public static let runTaskArgument = "--run-task"

    public let agentsDirectory: URL
    /// False in tests, where plists are written but launchd is left alone.
    public let managesLaunchd: Bool

    public init(agentsDirectory: URL = LaunchAgentScheduler.defaultDirectory, managesLaunchd: Bool = true) {
        self.agentsDirectory = agentsDirectory
        self.managesLaunchd = managesLaunchd
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private func label(for id: UUID) -> String {
        Self.labelPrefix + id.uuidString
    }

    private func plistURL(for id: UUID) -> URL {
        agentsDirectory.appendingPathComponent("\(label(for: id)).plist")
    }

    func plistData(for task: BackupTask, executablePath: String) throws -> Data? {
        var plist: [String: Any] = [
            "Label": label(for: task.id),
            "ProgramArguments": [executablePath, Self.runTaskArgument, task.id.uuidString],
            "ProcessType": "Background",
        ]
        if case .interval(let minutes) = task.schedule {
            guard minutes > 0 else { return nil }
            plist["StartInterval"] = minutes * 60
        } else {
            let entries = task.schedule.calendarEntries
            guard !entries.isEmpty else { return nil }
            plist["StartCalendarInterval"] = entries
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Makes launchd match the task. Safe to call repeatedly: unchanged agents are left
    /// running, and a moved app gets its path updated the next time it launches.
    public func sync(_ task: BackupTask, executablePath: String) throws {
        guard let data = try plistData(for: task, executablePath: executablePath) else {
            try remove(taskID: task.id)
            return
        }
        let url = plistURL(for: task.id)
        if (try? Data(contentsOf: url)) == data { return }

        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        unload(task.id)
        try data.write(to: url, options: .atomic)
        if managesLaunchd {
            try launchctl(["bootstrap", "gui/\(getuid())", url.path])
        }
    }

    public func remove(taskID: UUID) throws {
        let url = plistURL(for: taskID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        unload(taskID)
        try FileManager.default.removeItem(at: url)
    }

    private func unload(_ id: UUID) {
        guard managesLaunchd else { return }
        // Fails harmlessly when the agent isn't loaded.
        try? launchctl(["bootout", "gui/\(getuid())/\(label(for: id))"])
    }

    private func launchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CopyError.system("launchctl \(arguments[0]) failed with status \(process.terminationStatus)")
        }
    }
}
