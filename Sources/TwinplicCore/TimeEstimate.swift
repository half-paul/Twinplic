import Foundation

/// Works out how long a phase has left from how far it has come in the time it has taken.
public enum TimeEstimate {
    /// The first readings are too noisy to be useful.
    public static let warmUp: TimeInterval = 2
    /// A scan that outgrows the last run's folder count still isn't finished.
    static let maxScanFraction = 0.99

    /// Returns nil until there's enough to go on.
    public static func secondsLeft(
        _ progress: RunProgress, elapsed: TimeInterval, expectedDirectories: Int? = nil
    ) -> TimeInterval? {
        guard elapsed >= warmUp else { return nil }
        let done = fractionDone(progress, expectedDirectories: expectedDirectories)
        guard done > 0 else { return nil }
        return elapsed * (1 - done) / done
    }

    static func fractionDone(_ progress: RunProgress, expectedDirectories: Int?) -> Double {
        guard progress.phase == .scanning else { return progress.fraction }
        // The last run's count is far more accurate, because folders vary so much in size.
        if let expectedDirectories, expectedDirectories > 0 {
            return min(maxScanFraction, Double(progress.itemsDone) / Double(expectedDirectories))
        }
        return progress.scanPosition
    }
}

extension RunRecord {
    /// How many folders the next scan should visit, from the newest run that finished its scan.
    public static func expectedDirectories(from history: [RunRecord]) -> Int? {
        history.first { ($0.status == .success || $0.status == .completedWithErrors) && $0.directoriesScanned != nil }?
            .directoriesScanned
    }
}
