import TwinplicCore
import SwiftUI

struct PreviewSheet: View {
    private static let maxRows = 1_000

    @Environment(\.dismiss) private var dismiss
    let result: PreviewResult

    private var plan: BackupPlan { result.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview of “\(result.task.name)”")
                    .font(.headline)
                Text("Nothing has been changed yet.")
                    .foregroundStyle(.secondary)
            }
            .padding()

            HStack(spacing: 24) {
                stat("Files added", plan.copyCount)
                stat("Replaced", plan.updateCount)
                stat("Deleted", plan.deleteCount)
                HStack(alignment: .top, spacing: 4) {
                    stat("Unchanged", plan.unchangedCount)
                    HelpButton(tip: .unchanged)
                }
                VStack(alignment: .leading) {
                    Text(ByteCountFormatter.string(fromByteCount: plan.bytesToCopy, countStyle: .file))
                        .font(.title2.monospacedDigit())
                    Text("To copy").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)

            AccessBanner(problems: plan.access)
                .padding(.horizontal)
                .padding(.bottom, plan.access.isEmpty ? 0 : 12)

            Divider()

            if plan.isEmpty && plan.errors.isEmpty {
                ContentUnavailableView("Already Up to Date", systemImage: "checkmark.circle")
            } else {
                List {
                    if !plan.errors.isEmpty {
                        Section("Problems (these items will be skipped)") {
                            ForEach(plan.errors.prefix(Self.maxRows), id: \.self) { Text($0).font(.caption) }
                            if plan.errors.count > Self.maxRows {
                                Text("And \(plan.errors.count - Self.maxRows) more.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        ForEach(plan.items.prefix(Self.maxRows)) { ItemRow(item: $0) }
                        if plan.items.count > Self.maxRows {
                            Text("And \(plan.items.count - Self.maxRows) more.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading) {
            Text(value, format: .number).font(.title2.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ItemRow: View {
    let item: PlanItem

    var body: some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(item.relativePath)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if item.kind == .file {
                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch item.action {
        case .copyNew: "plus.circle.fill"
        case .update: "arrow.triangle.2.circlepath.circle.fill"
        case .delete: "minus.circle.fill"
        }
    }

    private var color: Color {
        switch item.action {
        case .copyNew: .green
        case .update: .blue
        case .delete: .red
        }
    }
}
