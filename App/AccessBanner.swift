import AppKit
import TwinplicCore
import SwiftUI

/// Says why items were refused and what can fix it. Shows nothing when there's nothing to do.
struct AccessBanner: View {
    @Environment(AppModel.self) private var model
    let problems: AccessProblems?

    private var privacyBlocked: Int {
        // With Full Disk Access already on, the cause is something else, such as a locked
        // file, and sending the user to Settings wouldn't help. History has the details.
        model.hasFullDiskAccess == true ? 0 : problems?.privacyBlocked ?? 0
    }

    private var noPermission: Int { problems?.noPermission ?? 0 }

    var body: some View {
        if privacyBlocked > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "macOS blocked \(count(privacyBlocked)), so Twinplic can't back them up. Turn on Full Disk Access for Twinplic, then quit and reopen it.",
                    systemImage: "lock.shield"
                )
                HStack {
                    Button("Open Full Disk Access Settings") { model.openFullDiskAccessSettings() }
                    Button("Show Twinplic in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            }
            .font(.callout)
        }
        if noPermission > 0 {
            Label(
                "\(count(noPermission).capitalizedFirst) can't be accessed because of their own permissions. Full Disk Access doesn't change this. Use Get Info in Finder to give your account access. History lists the items.",
                systemImage: "lock"
            )
            .font(.callout)
        }
    }

    private func count(_ items: Int) -> String {
        items == 1 ? "1 item" : "\(items) items"
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
