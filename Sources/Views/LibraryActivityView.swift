import SwiftUI

public struct LibraryActivityView: View {
    @EnvironmentObject private var activity: LibraryActivityStore
    @State private var filter = ActivityFilter.all
    @State private var showsClearConfirmation = false
    @State private var expandedIDs: Set<UUID> = []
    private let openHealth: () -> Void
    private let openSettings: () -> Void

    private enum ActivityFilter: String, CaseIterable, Identifiable {
        case all = "All", running = "Running", attention = "Warnings & Errors"
        var id: Self { self }
    }

    public init(openHealth: @escaping () -> Void = {}, openSettings: @escaping () -> Void = {}) {
        self.openHealth = openHealth
        self.openSettings = openSettings
    }

    private var visibleRecords: [LibraryActivityRecord] {
        activity.records.filter {
            switch filter {
            case .all: true
            case .running: !$0.status.isTerminal
            case .attention: $0.severity == .warning || $0.severity == .error
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Button("Clear History…") { showsClearConfirmation = true }
                    .disabled(!activity.records.contains(where: { $0.status.isTerminal }) && activity.storageIssue == nil)
                    .accessibilityIdentifier("activity.clearHistory")
            }
            HStack {
                Button("Library Health", action: openHealth).accessibilityIdentifier("activity.openHealth")
                Button("Settings", action: openSettings).accessibilityIdentifier("activity.openSettings")
            }
            Picker("Show activity", selection: $filter) {
                ForEach(ActivityFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if let issue = activity.storageIssue {
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visibleRecords.isEmpty {
                        Text(filter == .all ? "No recent activity." : "No activity matches this filter.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
                    }
                    ForEach(visibleRecords) { record in
                        activityRow(record)
                        Divider().padding(.vertical, 8)
                    }
                }
            }
            Text("History stores operation names, counts and filename-only failures for 30 days. Full messages stay in this session.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 560, height: 420)
        .confirmationDialog("Clear recent activity history?", isPresented: $showsClearConfirmation) {
            Button("Clear History", role: .destructive) { Task { await activity.clearHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Running operations remain visible. Clearing also replaces an unreadable history file.")
        }
        .task { await activity.load() }
    }

    private func activityRow(_ record: LibraryActivityRecord) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedIDs.contains(record.id) },
            set: { if $0 { expandedIDs.insert(record.id) } else { expandedIDs.remove(record.id) } }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                if let message = activity.liveMessages[record.id] {
                    Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if let counts = record.counts {
                    Text("Catalog saved: \(counts.catalogSaved) · Files saved: \(counts.filesSaved) of \(counts.filesAttempted) · Files failed: \(counts.filesFailed)")
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(record.failures.enumerated()), id: \.offset) { _, failure in
                    Text("\(failure.fileName): \(failure.category.title)").textSelection(.enabled)
                }
                if record.failureCount > record.failures.count {
                    Text("\(record.failureCount - record.failures.count) additional failure(s)").foregroundStyle(.secondary)
                }
                Text("Started \(record.startedAt.formatted(date: .abbreviated, time: .standard))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption).padding(.top, 4)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: record.severity == .error ? "xmark.octagon.fill"
                      : record.severity == .warning ? "exclamationmark.triangle.fill"
                      : record.status == .running ? "clock" : "checkmark.circle")
                    .foregroundStyle(record.severity == .error ? Color.red : record.severity == .warning ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).fontWeight(.medium)
                    Text(record.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if activity.canCancel(id: record.id) {
                    Button("Cancel") { activity.cancel(id: record.id) }
                        .accessibilityIdentifier("activity.cancel.\(record.id.uuidString)")
                }
                Text(record.updatedAt, style: .time).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("activity.record.\(record.id.uuidString)")
    }
}
