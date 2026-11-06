import TwinplicCore
import Foundation

/// The Help window's pages. Text is Markdown, and a line starting with "• " is a list item.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, creatingBackup, running, pausing, options, safetyNet, schedule
    case excludes, previewDryRun, history, restoring, permissions, menuBar, dataProtection
    case troubleshooting, limits

    var id: Self { self }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .creatingBackup: "Creating a Backup"
        case .running: "Running a Backup"
        case .pausing: "Pause and Stop"
        case .options: "Backup Options"
        case .safetyNet: "SafetyNet"
        case .schedule: "Scheduling"
        case .excludes: "Excluding Items"
        case .previewDryRun: "Preview and Dry Run"
        case .history: "History"
        case .restoring: "Restoring Files"
        case .permissions: "Permissions"
        case .menuBar: "Menu Bar and Login"
        case .dataProtection: "How Your Data Is Protected"
        case .troubleshooting: "Troubleshooting"
        case .limits: "Limits"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "star"
        case .creatingBackup: "plus.circle"
        case .running: "play.circle"
        case .pausing: "pause.circle"
        case .options: "slider.horizontal.3"
        case .safetyNet: "shield.lefthalf.filled"
        case .schedule: "calendar"
        case .excludes: "minus.circle"
        case .previewDryRun: "eye"
        case .history: "clock.arrow.circlepath"
        case .restoring: "arrow.uturn.backward.circle"
        case .permissions: "lock.shield"
        case .menuBar: "menubar.rectangle"
        case .dataProtection: "checkmark.shield"
        case .troubleshooting: "wrench.and.screwdriver"
        case .limits: "exclamationmark.triangle"
        }
    }

    var sections: [HelpSection] {
        switch self {
        case .gettingStarted:
            [
                HelpSection(nil, """
                Twinplic backs up a folder or disk to another folder or disk. After the first run it copies only what changed, and it keeps replaced and removed files in a SafetyNet folder for a while in case you need them back.
                """),
                HelpSection("Your first backup", """
                • Choose **New Backup** with the + button, or press ⌘N.
                • Click **Source** and choose what to back up.
                • Click **Destination** and choose where the backup goes, usually on another disk.
                • Choose **Preview** to see what would be copied. Nothing is changed.
                • Choose **Back Up Now**.
                """),
                HelpSection("Getting help in the app", """
                Click the question mark beside a control for a short explanation. **Learn More** in that popup opens the matching page here. Press ⌘? to open this window at any time.
                """),
                HelpSection("Keyboard shortcuts", """
                • ⌘N: new backup
                • ⌘?: Twinplic Help
                • ⌘Q: quit, from the menu bar icon's menu or the app menu
                """),
            ]
        case .creatingBackup:
            [
                HelpSection(nil, """
                Each backup task has a name, a source and a destination. The list on the left shows every task with its status and when it last ran.
                """),
                HelpSection("Source and Destination", """
                Click a card to choose a folder or disk. The card shows the name of what you chose, and the free space on that disk. Hover over a card to see the full path.

                The source and destination can't be the same folder, and one can't be inside the other.
                """),
                HelpSection("Using a destination that already has files", """
                Twinplic marks every destination it uses with a small hidden file. If you choose a folder that has files but no marker, Twinplic stops and asks first, because a backup could replace or remove those files. You can choose:

                • **Preview Changes** to see exactly what would happen.
                • **Back Up Anyway** to take over the folder.
                • **Cancel** to leave it alone.

                Scheduled runs never get this choice, so run an unrecognized destination by hand once before scheduling it.
                """),
                HelpSection("Deleting a task", """
                Control-click a task in the list and choose **Delete…**. This removes the task, its schedule and its history. Files already backed up stay on the destination. A task can't be deleted while it's running.
                """),
            ]
        case .running:
            [
                HelpSection(nil, """
                Choose **Back Up Now** to run a task. If **Dry run** is on, the button reads **Dry Run Now** and nothing is written.
                """),
                HelpSection("What happens during a run", """
                • **Safety checks** make sure the disks are connected and the run can't damage data.
                • **Scanning** compares the source and destination.
                • **Removing extras** clears items that no longer belong, in Mirror mode.
                • **Copying** copies new and changed files.
                • **Verifying** checks each copy, if that option is on.
                • **Finishing** restores folder dates and cleans up old SafetyNet items.
                """),
                HelpSection("Reading the status bar", """
                The bar shows the current stage, the file being worked on, how much is done, the speed and the time left.

                Time left appears after about two seconds and covers the current stage only. A scan can't include the copying that follows it, because how much there is to copy isn't known until the scan ends.

                A scan is timed against the folder count of the last finished run. With no earlier run, it uses its position in the folder tree, which is rougher.
                """),
                HelpSection("While a task runs", """
                Its settings are locked until it finishes. You can still read every help popup. Other tasks can run at the same time.
                """),
            ]
        case .pausing:
            [
                HelpSection("Pause", """
                **Pause** stops a run or preview where it is, even part way through a large file, and frees the CPU and disk. Choose **Continue** to carry on from the same place.

                A paused run continues by itself after 15 minutes, and a countdown shows the time left. To hold it longer, choose **Continue** and then **Pause** again, which restarts the 15 minutes.

                Scheduled runs have the same button in their progress window.
                """),
                HelpSection("Changes made during a pause", """
                A paused run keeps the plan it made before the pause. If a file changes while it's half copied, that copy is thrown away and reported as an error, so a part old, part new file never reaches the backup. The next run copies it properly.

                Other changes made during a pause are picked up by the next run. If you want them included now, choose **Stop** and run the backup again.
                """),
                HelpSection("Stop", """
                **Stop** ends a run early, and works while paused. Files already copied stay in the backup, and the file being copied is discarded, so no partial file is left. The next run picks up what's left.

                Stopping a preview closes it without showing partial results.
                """),
                HelpSection("Things that can't be interrupted", """
                Pause and Stop take effect at the next safe point. Removing one large folder, cleaning up SafetyNet and cloning a file on APFS finish first.
                """),
            ]
        case .options:
            [
                HelpSection("Mode", """
                • **Mirror source** makes the destination match the source. Items you remove from the source are removed from the destination too.
                • **Only add and update** never removes anything because it's gone from the source, so files you delete stay in the backup.
                """),
                HelpSection("SafetyNet", """
                Keeps replaced and removed items for a number of days instead of deleting them. See the SafetyNet page.
                """),
                HelpSection("Verify each copied file", """
                Reads the original and the new copy, and compares their SHA-256 checksums before accepting the copy. This catches a bad disk or cable, but a run takes longer because every copied file is read twice more.

                Files that were skipped as unchanged aren't re-checked.
                """),
                HelpSection("Dry run", """
                Makes every run of this task, manual or scheduled, write nothing to the destination. See the Preview and Dry Run page. Dry runs never back anything up, so turn this off when you're done.
                """),
            ]
        case .safetyNet:
            [
                HelpSection(nil, """
                With SafetyNet on, a file that a run would replace or remove is moved to a dated folder on the destination instead. It's a quick move on the same disk, not a second copy.
                """),
                HelpSection("Where items go", """
                Items are kept in `\(Reserved.safetyNetFolder)` at the top of the destination, in one folder per run, named with the date and time in UTC. Each item keeps its place in the folder structure.
                """),
                HelpSection("How long items are kept", """
                Choose from 1 to 365 days. The default is 30. Older run folders are deleted at the end of each finished run, so a task that stops running keeps its old items until it runs again.

                These items use space on the destination. If the disk fills up, lower the number of days.
                """),
                HelpSection("Turning it off", """
                With SafetyNet off, replaced and removed items are deleted permanently. Twinplic shows a warning under the toggle.
                """),
            ]
        case .schedule:
            [
                HelpSection(nil, """
                Scheduled backups run even when Twinplic is closed. If your Mac is asleep at the scheduled time, the backup runs when it wakes. A Mac that's shut down misses that run.
                """),
                HelpSection("Schedule types", """
                • **Manually**: runs only when you choose Back Up Now.
                • **Every few minutes or hours**: every 5 to 720 minutes, in steps of 5, or every 1 to 24 hours.
                • **Every hour**: at a chosen number of minutes past the hour.
                • **On days of the week**: on chosen days, at one or more times. **Every Day**, **Weekdays** and **Weekends** are quick choices.
                • **On days of the month**: on chosen dates, at one or more times. A month without a chosen date skips it.

                At least one day stays selected. Use **Add Time** for more than one run a day. **Next run** shows when the task will run, except for repeating intervals, which macOS counts from when the schedule was loaded.
                """),
                HelpSection("Skip scheduled runs on battery power", """
                Skips a scheduled run while your Mac is on battery, and notes it in History. Manual runs aren't affected.
                """),
                HelpSection("What you see during a scheduled run", """
                A small floating window shows progress, with **Pause** and **Stop**. Closing it only hides it, and the run carries on. Quick runs finish before it appears. The main window doesn't show a live progress bar for these runs, but the result appears in History.

                A scheduled run won't start if the same task is already running or paused.
                """),
            ]
        case .excludes:
            [
                HelpSection(nil, """
                Excluded items aren't copied, and aren't removed from the destination. Enter one name or pattern per line.
                """),
                HelpSection("Patterns", """
                Each line is tested against an item's name and against its path inside the source. Upper and lower case are treated as different.

                • `node_modules` skips anything with that name, including everything in a folder of that name.
                • `*.tmp` skips every name ending in .tmp.
                • `Photos/Exports` skips that one path.
                • `cache?` matches one extra character, such as cache1.
                """),
                HelpSection("Excluded by default", """
                New tasks start with macOS housekeeping files: \(BackupTask.defaultExcludes.map { "`\($0)`" }.joined(separator: ", ")). You can edit this list.
                """),
            ]
        case .previewDryRun:
            [
                HelpSection("Preview", """
                **Preview** scans once and shows what a run would do, without changing anything or adding to History. It lists files added, replaced, deleted and unchanged, how much would be copied, and any problems. The list shows the first 1,000 items.
                """),
                HelpSection("Dry run", """
                With **Dry run** on, every run does its safety checks and scan, then logs what would change in History instead of doing it. This includes scheduled runs, so it's a good way to try a schedule. The first 200 changes are listed in History.

                Dry runs and previews can use a destination Twinplic doesn't recognize, because they write nothing.
                """),
                HelpSection("What unchanged means", """
                A file counts as unchanged if its size and modification time match, or a symlink if its target matches. This is the same test a backup uses to skip a file. Contents aren't compared. Folders and excluded items aren't counted.
                """),
            ]
        case .history:
            [
                HelpSection(nil, """
                History keeps the last \(TaskStore.maxHistoryPerTask) runs of each task, newest first. Each row shows the result, the time, what changed and how much was copied. Click a row to see its errors, or the changes a dry run listed.
                """),
                HelpSection("Results", """
                • **Completed**: the run finished with no problems.
                • **Completed with errors**: the run finished, but some items failed. Open the row to see which. The first 200 errors are kept.
                • **Stopped**: you stopped it.
                • **Didn't run**: a safety check stopped it before anything changed.
                • **Skipped**: a schedule skipped it, for example on battery.
                """),
            ]
        case .restoring:
            [
                HelpSection(nil, """
                A backup is a normal folder of normal files, so you don't need Twinplic to get anything back.
                """),
                HelpSection("Getting a file back", """
                • Open the destination in Finder and copy the file back to where you want it.
                • For an older version or a removed file, open `\(Reserved.safetyNetFolder)` on the destination, then the folder for the run that replaced or removed it. Dates are in UTC.
                """),
                HelpSection("Before you restore", """
                Don't point a task's source at its backup to restore it. With Mirror source on, a task always makes the destination match the source. To restore a lot of files, create a separate task with the backup as its source, and use **Preview** first.

                To see hidden items in Finder, press ⌘⇧. (Command, Shift, full stop).
                """),
            ]
        case .permissions:
            [
                HelpSection(nil, """
                macOS asks for your permission the first time Twinplic reaches Desktop, Documents, Downloads, a removable disk or a network disk. Other protected data, such as Mail and Safari, needs Full Disk Access.
                """),
                HelpSection("Turning on Full Disk Access", """
                An app can't grant this to itself, and macOS has no prompt for it. If macOS blocks anything, Twinplic shows an alert once per launch, and a banner on the task until a run finishes without being blocked.

                • Choose **Open Full Disk Access Settings**.
                • Turn on Twinplic. If it isn't listed, choose **Show Twinplic in Finder** and drag it into the list.
                • Quit and reopen Twinplic.

                Scheduled runs show no alert. They record the block in History, and the banner appears when you next open the app.
                """),
                HelpSection("Files with their own permissions", """
                Full Disk Access doesn't help with an item's own permissions, such as a file owned by another user. Twinplic reports these separately. In Finder, choose **Get Info** on the item and give your account access.
                """),
                HelpSection("What happens to blocked items", """
                A folder that can't be read is skipped, and its existing backup stays in place. Twinplic never treats a folder it can't read as an empty one.
                """),
            ]
        case .menuBar:
            [
                HelpSection("Menu bar icon", """
                Closing the main window keeps Twinplic running as a menu bar icon, with no Dock icon. The icon changes during a run, and its menu lists running tasks with their progress. Use it to reopen the window, open Help or quit.
                """),
                HelpSection("Launch at Login", """
                Choose **Launch at Login** from the menu bar icon to start Twinplic at login, in the menu bar with no window. Scheduled backups run without this option. You can also manage it in System Settings > General > Login Items & Extensions.
                """),
            ]
        case .dataProtection:
            [
                HelpSection("Checks before every run", """
                • A run stops if a disk isn't connected, including when an empty `/Volumes/Name` folder is left on the startup disk.
                • Mirroring stops if the source is empty but the destination isn't, because an unplugged or wiped source looks like everything was deleted.
                • A destination with files but no Twinplic marker needs your consent. Scheduled runs never get it.
                """),
                HelpSection("During a run", """
                • A source folder that can't be read is skipped, and its backup stays in place.
                • Files are copied to a temporary name and renamed once complete, so an interrupted run leaves no partial file under the real name, and the old version survives until the new one is ready.
                • Permissions, extended attributes and ACLs are kept. On APFS, copies within a disk are clones where possible.
                • One task can't run twice at once, even from the app and a schedule.
                """),
                HelpSection("Items Twinplic adds to a destination", """
                • `\(Reserved.markerFile)`: marks the folder as a Twinplic destination.
                • `\(Reserved.safetyNetFolder)`: holds SafetyNet items.
                • Names starting with `\(Reserved.tempPrefix)`: files being copied. Any left by an interrupted run are removed by the next one.
                """),
                HelpSection("Where settings are kept", """
                Tasks and history are in `~/Library/Application Support/Twinplic`.
                """),
            ]
        case .troubleshooting:
            [
                HelpSection("“The disk isn't connected”", """
                Connect the disk and try again. Twinplic refuses to write to a leftover folder in `/Volumes`, because that would fill your startup disk.
                """),
                HelpSection("“The source is empty but the destination has files”", """
                Check the source disk is connected and has your files. If you really emptied it, use **Only add and update**, or clear the destination yourself.
                """),
                HelpSection("A run says “Completed with errors”", """
                Open the run in History to see which items failed. A permissions message means the Permissions page applies. Items that failed are tried again on the next run.
                """),
                HelpSection("“It changed while the run was paused”", """
                The file was edited during a pause, so its copy was discarded. The next run copies it.
                """),
                HelpSection("A scheduled backup didn't run", """
                • Check the Mac was on. A shut down Mac misses that run.
                • Check History for a skipped run if **Skip scheduled runs on battery power** is on.
                • A destination Twinplic doesn't recognize shows as **Didn't run** in History. Run it by hand once.
                • Open Twinplic from the copy of the app you use, so the schedule points to it.
                """),
                HelpSection("Full Disk Access is on but Twinplic is still blocked", """
                Quit and reopen Twinplic. If you replaced the app with a different build, remove it from the Full Disk Access list and add it again.
                """),
                HelpSection("A scan takes a long time", """
                Scanning a network share is limited by how fast the server lists folders. Exclude folders you don't need, or schedule the run for a quiet time.
                """),
            ]
        case .limits:
            [
                HelpSection(nil, """
                • Backups aren't bootable. Bootable copies need Apple's `asr` tool and a privileged helper.
                • Hard links are copied as separate files.
                • Clones within one APFS volume are instant, so the progress bar jumps per file there.
                • Scheduled runs happen in a separate process, so the main window shows their result in History but not a live progress bar.
                • A Mac that's shut down at the scheduled time misses that run.
                • Change detection uses size and modification time. A file edited without changing either isn't copied.
                • Time left is an estimate for the current stage.
                """),
            ]
        }
    }

    var searchText: String {
        ([title] + sections.flatMap { [$0.heading ?? "", $0.body] }).joined(separator: " ")
    }
}

struct HelpSection: Identifiable {
    let heading: String?
    let body: String

    var id: String { (heading ?? "") + body.prefix(24) }

    init(_ heading: String?, _ body: String) {
        self.heading = heading
        self.body = body
    }
}

/// The popup beside a control. `topic` is the Help page its Learn More link opens.
enum HelpTip {
    case source, destination, preview, backUpNow, dryRunNow, pause, stop
    case mode, safetyNet, verify, dryRun, schedule, skipOnBattery, excludes, history, unchanged

    var title: String {
        switch self {
        case .source: "Source"
        case .destination: "Destination"
        case .preview: "Preview"
        case .backUpNow: "Back Up Now"
        case .dryRunNow: "Dry Run Now"
        case .pause: "Pause"
        case .stop: "Stop"
        case .mode: "Mode"
        case .safetyNet: "SafetyNet"
        case .verify: "Verify each copied file"
        case .dryRun: "Dry run"
        case .schedule: "Schedule"
        case .skipOnBattery: "Skip on battery power"
        case .excludes: "Exclude"
        case .history: "History"
        case .unchanged: "Unchanged"
        }
    }

    var message: String {
        switch self {
        case .source:
            "The folder or disk to back up. Twinplic only reads from it, and never changes it."
        case .destination:
            "Where the backup goes, usually on another disk. If the folder already has files Twinplic didn't put there, it asks before doing anything."
        case .preview:
            "Shows what a run would add, replace, delete and leave unchanged. Nothing is changed, and nothing is added to History."
        case .backUpNow:
            "Runs the backup now. After the first run, only what changed is copied."
        case .dryRunNow:
            "Dry run is on, so this logs what would change in History and writes nothing. Turn it off in Options to back up."
        case .pause:
            "Stops the run where it is and frees the CPU and disk. It continues by itself after 15 minutes, or when you choose Continue."
        case .stop:
            "Ends the run early. Files already copied stay in the backup, no partial file is left, and the next run picks up the rest."
        case .mode:
            "Mirror source makes the destination match the source, so items you remove are removed from the backup too. Only add and update never removes them."
        case .safetyNet:
            "Keeps replaced and removed items in a dated folder on the destination for the days you choose. With it off, they're deleted permanently."
        case .verify:
            "Compares a checksum of each copy with the original before accepting it. Safer, but runs take longer."
        case .dryRun:
            "Every run of this task, including scheduled ones, only logs what would change. Nothing is backed up until you turn this off."
        case .schedule:
            "Runs this backup automatically, even when Twinplic is closed. A sleeping Mac runs it on wake. A shut down Mac misses that run."
        case .skipOnBattery:
            "Skips scheduled runs while your Mac is on battery, and notes it in History. Manual runs aren't affected."
        case .excludes:
            "Items that match aren't copied, and aren't removed from the destination. Enter one name or pattern per line, such as node_modules or *.tmp."
        case .history:
            "The last \(TaskStore.maxHistoryPerTask) runs of this task. Click a run to see its errors, or what a dry run would have changed."
        case .unchanged:
            "Files that already match by size and modification time, so a run would skip them. Contents aren't compared."
        }
    }

    var topic: HelpTopic {
        switch self {
        case .source, .destination: .creatingBackup
        case .preview, .dryRunNow, .dryRun, .unchanged: .previewDryRun
        case .backUpNow: .running
        case .pause, .stop: .pausing
        case .mode, .verify: .options
        case .safetyNet: .safetyNet
        case .schedule, .skipOnBattery: .schedule
        case .excludes: .excludes
        case .history: .history
        }
    }
}
