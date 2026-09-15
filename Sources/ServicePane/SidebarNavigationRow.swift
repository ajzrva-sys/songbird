import SwiftUI

struct SidebarNavigationRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let supportsSearch: Bool
    var badgeCount: Int? = nil
    var foregroundColor: Color? = nil
    var metrics: ServicePaneMetrics = .standard
    var doubleClickAction: (() -> Void)? = nil
    let action: () -> Void

    @EnvironmentObject private var librarySearch: LibrarySearchCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool

    private var presentsSearchField: Bool {
        isSelected && supportsSearch && librarySearch.isPresented
    }

    var body: some View {
        HStack(spacing: 8) {
            if presentsSearchField {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: metrics.iconColumnWidth, alignment: .center)

                TextField("Search \(title)", text: $librarySearch.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .onKeyPress(.escape, action: dismissSearch)
                    .onChange(of: searchFocused) { wasFocused, isFocused in
                        if wasFocused && isFocused == false {
                            librarySearch.collapseIfEmpty()
                        }
                    }

                if librarySearch.query.isEmpty == false {
                    Button("Clear Search", systemImage: "xmark.circle.fill", action: clearSearch)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: metrics.iconColumnWidth, alignment: .center)
                        Text(title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let badgeCount {
                            Text("\(badgeCount)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                    .overlay {
                        if let doubleClickAction {
                            MacClickActivationView(
                                singleClick: { _ in action() },
                                doubleClick: doubleClickAction
                            )
                        }
                    }
                }
                .buttonStyle(.plain)

                if isSelected && supportsSearch {
                    Button("Search \(title)", systemImage: "magnifyingglass") {
                        librarySearch.requestFocus()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Search \(title)")
                }
            }
        }
        .foregroundStyle(foregroundColor ?? SongbirdTheme.text(for: colorScheme))
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: metrics.selectionCornerRadius)
                .fill(
                    isSelected
                        ? SongbirdTheme.sidebarSelected(for: colorScheme)
                        : Color.clear
                )
        }
        .contentShape(Rectangle())
        .focusedValue(
            \.librarySearchCommands,
            isSelected && supportsSearch && searchFocused == false
                ? FocusedLibrarySearchCommands(focusSearch: librarySearch.requestFocus)
                : nil
        )
        .task(id: librarySearch.focusRequestID) {
            guard presentsSearchField else { return }
            await Task.yield()
            searchFocused = true
        }
    }

    private func clearSearch() {
        librarySearch.clear()
        searchFocused = true
    }

    private func dismissSearch() -> KeyPress.Result {
        searchFocused = false
        librarySearch.dismiss()
        return .handled
    }
}
