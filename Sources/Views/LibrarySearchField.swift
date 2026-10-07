import SwiftUI

/// One persistent field for the visible collection. The owner keeps focus state
/// so text editing cannot be mistaken for the table's type-to-select gestures.
struct LibrarySearchField: View {
    let scopeTitle: String
    let focused: FocusState<Bool>.Binding
    var identifier = "library.search"

    @EnvironmentObject private var search: LibrarySearchCoordinator

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search \(scopeTitle)", text: $search.query)
                .textFieldStyle(.plain)
                .focused(focused)
                .accessibilityLabel("Search \(scopeTitle)")
                .accessibilityIdentifier(identifier)
                .onSubmit { focused.wrappedValue = false }
                .onKeyPress(.escape) {
                    search.dismiss()
                    focused.wrappedValue = false
                    return .handled
                }
            if !search.query.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    search.clear()
                    focused.wrappedValue = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear Search")
                .accessibilityInputLabels(["Clear Search", "Clear"])
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 9)
        .frame(minWidth: 160, idealWidth: 240, maxWidth: 320, minHeight: 30)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .onChange(of: search.focusRequestID) { _, _ in
            focused.wrappedValue = true
        }
    }
}
