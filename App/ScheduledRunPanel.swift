import AppKit
import TwinplicCore
import Observation
import SwiftUI

/// A launchd run has no app window, so it shows its own floating progress panel. That
/// keeps Stop in this process, and it works whether or not the main app is open.
@MainActor
enum ScheduledRunPanel {
    /// Quick runs finish before this, so a run with nothing to do never flashes a window.
    private static let showDelay = Duration.seconds(1)

    /// Runs `task` under an event loop, then exits with the run's status.
    static func run(_ task: BackupTask, store: TaskStore) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let engine = BackupEngine(task: task)
        let state = ScheduledRunState(engine: engine, history: (try? store.loadHistory(for: task.id)) ?? [])
        let throttle = ProgressThrottle { state.run.update(with: $0) }

        Task {
            try? await Task.sleep(for: showDelay)
            show(ScheduledRunView(task: task, state: state))
        }

        Task {
            let outcome = await Task.detached { () -> Result<RunRecord, Error> in
                Result {
                    // Scheduled runs never get consent to take over an unrecognized destination.
                    try TaskRunner.runScheduled(engine, store: store, progress: throttle.submit)
                }
            }.value

            switch outcome {
            case .success(let record):
                exit(record.status == .success || record.status == .skipped ? 0 : 1)
            case .failure(let error):
                fputs("Twinplic: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        app.run()
        exit(1)
    }

    private static func show(_ view: ScheduledRunView) {
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Twinplic"
        panel.contentView = hosting
        panel.level = .floating
        // Closing only hides the panel. The run carries on.
        panel.isReleasedWhenClosed = false
        // This process is never the active app, and panels hide by default when it isn't.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - panel.frame.width - 20, y: screen.maxY - 20))
        }
        panel.orderFrontRegardless()
    }
}

@MainActor
@Observable
private final class ScheduledRunState {
    var run: ActiveRun
    var isStopping = false

    init(engine: BackupEngine, history: [RunRecord]) {
        run = ActiveRun(engine: engine, history: history)
    }

    func stop() {
        isStopping = true
        run.stop()
    }
}

private struct ScheduledRunView: View {
    let task: BackupTask
    let state: ScheduledRunState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.dryRun ? "Dry run of “\(task.name)”" : "Backing up “\(task.name)”")
                .font(.headline)
                .lineLimit(1)
            RunStatusView(run: state.run, lastRun: nil, stacked: true)
            HStack {
                Spacer()
                Button(state.run.isPaused ? "Continue" : "Pause") { state.run.togglePause() }
                    .disabled(state.isStopping)
                Button(state.isStopping ? "Stopping…" : "Stop") { state.stop() }
                    .disabled(state.isStopping)
            }
        }
        .padding()
        .frame(width: 440)
    }
}
