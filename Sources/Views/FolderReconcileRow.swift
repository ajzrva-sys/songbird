import SwiftUI

/// Shared row for folder-reconciliation review flows (album, artist).
struct FolderReconcileRow: View {
    let title: String
    let subtitle: String
    let parsedValue: String
    let onApply: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("→ \(parsedValue)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.blue)

            Button("Apply") { onApply() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Skip") { onSkip() }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}
