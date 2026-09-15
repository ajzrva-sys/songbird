import SwiftUI

public struct LibraryStatusBar: View {
    @EnvironmentObject private var importProgress: ImportProgressState
    @EnvironmentObject private var notices: UserNoticeState
    @EnvironmentObject private var summary: LibrarySummaryState
    @Environment(\.colorScheme) private var colorScheme

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
