import SwiftUI

public struct LibraryStatusBar: View {
    @EnvironmentObject private var importProgress: ImportProgressState
    @EnvironmentObject private var notices: UserNoticeState
    @EnvironmentObject private var summary: LibrarySummaryState
    @EnvironmentObject private var activity: LibraryActivityStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsActivity = false
    private let openHealth: () -> Void
    private let openSettings: () -> Void

    public init(openHealth: @escaping () -> Void = {}, openSettings: @escaping () -> Void = {}) {
        self.openHealth = openHealth
        self.openSettings = openSettings
    }

    private static let barHeight: CGFloat = 22

    private var textColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }

    public var body: some View {
        HStack(spacing: 12) {
            if importProgress.value.isRunning {
                importContent
            } else if let notice = notices.notice {
                noticeContent(notice)
            } else {
                restingContent
            }
            Spacer()
            if importProgress.value.isRunning, let notice = notices.notice, notice.severity.isSticky {
                Button {
                    showsActivity = true
                } label: {
                    Label(notice.severity.activityTitle, systemImage: icon(for: notice.severity))
                }
                .foregroundStyle(color(for: notice.severity))
                .buttonStyle(.borderless)
                .help(notice.message)
                .accessibilityIdentifier("activity.currentWarning")
            }
            Button {
                showsActivity.toggle()
            } label: {
                Label(activity.attentionCount > 0 ? "Activity (\(activity.attentionCount))" : "Activity",
                      systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.borderless)
            .help("Show full messages and recent library operations")
            .accessibilityIdentifier("activity.show")
            .popover(isPresented: $showsActivity, arrowEdge: .top) {
                LibraryActivityView(openHealth: {
                    showsActivity = false
                    openHealth()
                }, openSettings: {
                    showsActivity = false
                    openSettings()
                }).environmentObject(activity)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .background(SongbirdTheme.nowPlayingBar(for: colorScheme))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SongbirdTheme.divider(for: colorScheme))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var importContent: some View {
        if importProgress.value.total > 0 {
            ProgressView(
                value: Double(importProgress.value.completed),
                total: Double(importProgress.value.total)
            )
            .progressViewStyle(.linear)
            .frame(width: 96)
        } else {
            ProgressView()
                .controlSize(.small)
        }
        Text(importProgress.value.message)
            .foregroundColor(textColor)
            .lineLimit(1)
            .help(importProgress.value.message)
        if importProgress.value.phase == .cancelling {
            Button("Cancelling…") {}
                .disabled(true)
                .controlSize(.small)
        } else {
            Button("Cancel") {
                LibraryStatus.shared.cancelImport()
            }
            .controlSize(.small)
        }
    }

    private func noticeContent(_ notice: LibraryNotice) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: notice.severity))
                .foregroundStyle(color(for: notice.severity))
            Text(label(for: notice.severity))
                .fontWeight(.semibold)
                .foregroundStyle(color(for: notice.severity))
            Text(notice.message)
                .foregroundColor(textColor)
                .lineLimit(1)
                .help(notice.message)
            if notice.isDismissible {
                Button("Dismiss") {
                    LibraryStatus.shared.dismissCurrentNotice()
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var restingContent: some View {
        if summary.summary != .none {
            Text(summary.summary.text)
                .foregroundColor(textColor)
        }
    }

    private func icon(for severity: LibraryNoticeSeverity) -> String {
        switch severity {
        case .information: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func label(for severity: LibraryNoticeSeverity) -> String {
        switch severity {
        case .information: return "Info"
        case .success: return "Success"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    private func color(for severity: LibraryNoticeSeverity) -> Color {
        switch severity {
        case .information: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
