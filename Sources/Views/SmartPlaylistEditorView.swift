import SwiftUI
import SwiftData

public struct SmartPlaylistEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore

    @State private var name: String
    @State private var matchMode: SmartMatchMode
    @State private var conditions: [SmartCondition]
    @State private var limitEnabled: Bool
    @State private var limitCount: Int
    @State private var limitUnit: SmartLimitUnit
    @State private var limitSortOrder: SmartLimitSortOrder
    @State private var liveMatchCount: Int?

    private let existingTarget: SmartPlaylistEditorTarget?
    private let onSavedModel: ((Playlist) -> Void)?
    private let onSavedID: ((UUID) -> Void)?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ruleSet: SmartPlaylistRuleSet {
        SmartPlaylistRuleSet(
            matchMode: matchMode,
            conditions: conditions,
            limitEnabled: limitEnabled,
            limitCount: limitCount,
            limitUnit: limitUnit,
            limitSortOrder: limitSortOrder
        )
    }

    private var canSave: Bool {
        trimmedName.isEmpty == false && ruleSet.validationErrors.isEmpty
    }

    private var matchRequestID: String {
        let conditionText = conditions.map { "\($0.id)|\($0.field.rawValue)|\($0.op.rawValue)|\($0.value)" }
            .joined(separator: ";")
        return "\(librarySnapshots.snapshot.revision)|\(matchMode.rawValue)|\(conditionText)"
    }

    @MainActor
    public init(playlist: Playlist? = nil, onSaved: ((Playlist) -> Void)? = nil) {
        self.init(
            target: playlist.map(SmartPlaylistEditorTarget.init(playlist:)),
            onSavedModel: onSaved,
            onSavedID: nil
        )
    }

    init(target: SmartPlaylistEditorTarget?, onSavedID: ((UUID) -> Void)? = nil) {
        self.init(target: target, onSavedModel: nil, onSavedID: onSavedID)
    }

    private init(
        target: SmartPlaylistEditorTarget?,
        onSavedModel: ((Playlist) -> Void)?,
        onSavedID: ((UUID) -> Void)?
    ) {
        existingTarget = target
        self.onSavedModel = onSavedModel
        self.onSavedID = onSavedID
        _name = State(initialValue: target?.name ?? "Smart Playlist")
        if let rules = target?.rules {
            _matchMode = State(initialValue: rules.matchMode)
            _conditions = State(initialValue: rules.conditions.map(Self.normalized))
            _limitEnabled = State(initialValue: rules.limitEnabled)
            _limitCount = State(initialValue: rules.limitCount)
            _limitUnit = State(initialValue: rules.limitUnit)
            _limitSortOrder = State(initialValue: rules.limitSortOrder)
        } else {
            _matchMode = State(initialValue: .all)
            _conditions = State(initialValue: [SmartCondition()])
            _limitEnabled = State(initialValue: false)
            _limitCount = State(initialValue: 25)
            _limitUnit = State(initialValue: .songs)
            _limitSortOrder = State(initialValue: .random)
        }
    }

    private static func normalized(_ condition: SmartCondition) -> SmartCondition {
        var condition = condition
        let operators = SmartOperator.operators(for: condition.field)
        if operators.contains(condition.op) == false {
            condition.op = operators[0]
        }
        if condition.op.requiresValue == false { condition.value = "" }
        return condition
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Playlist Builder")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Match mode row
            HStack(spacing: 6) {
                Text("Match")
                Picker("", selection: $matchMode) {
                    Text("all").tag(SmartMatchMode.all)
                    Text("any").tag(SmartMatchMode.any)
                }
                .labelsHidden()
                .frame(width: 80)
                Text("of the following condition(s):")
                Spacer()
            }
            .font(.system(size: 12))

            ScrollView {
            // Conditions list
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array($conditions.enumerated()), id: \.element.id) { index, $condition in
                    VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Picker("Field", selection: $condition.field) {
                            ForEach(SmartField.allCases) { field in
                                Text(field.label).tag(field)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .onChange(of: condition.field) { _, field in
                            let operators = SmartOperator.operators(for: field)
                            if operators.contains(condition.op) == false {
                                condition.op = operators[0]
                            }
                            if condition.op.requiresValue == false {
                                condition.value = ""
                            }
                        }

                        Picker("Operator", selection: $condition.op) {
                            ForEach(SmartOperator.operators(for: condition.field)) { op in
                                Text(op.label).tag(op)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .onChange(of: condition.op) { _, op in
                            if op.requiresValue == false {
                                condition.value = ""
                            }
                        }

                        if condition.op.requiresValue {
                            TextField(valuePrompt(for: condition.field), text: $condition.value)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Spacer()
                        }

                        // Add/Remove buttons
                        HStack(spacing: 4) {
                            Button {
                                conditions.remove(at: index)
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.borderless)
                            .disabled(conditions.count <= 1)

                            Button {
                                conditions.insert(SmartCondition(), at: index + 1)
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.borderless)
                        }

                        if let error = SmartPlaylistRuleSet.validationError(for: condition) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .help(error.localizedDescription)
                        }
                    }
                    if let error = SmartPlaylistRuleSet.validationError(for: condition) {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    }
                }
            }

            // Limit section
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Toggle("", isOn: $limitEnabled)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                    Text("Limit to")
                        .font(.system(size: 12))
                    TextField("", value: $limitCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .disabled(!limitEnabled)
                    Picker("", selection: $limitUnit) {
                        ForEach(SmartLimitUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .disabled(!limitEnabled)
                    Text("Selected by")
                        .font(.system(size: 12))
                    Picker("", selection: $limitSortOrder) {
                        ForEach(SmartLimitSortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .disabled(!limitEnabled)
                    Spacer()
                }
                .font(.system(size: 12))
            }

            if let liveMatchCount {
                Text("\(liveMatchCount) matching \(liveMatchCount == 1 ? "track" : "tracks")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Checking matches…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }

            Spacer()

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    if save() { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(canSave == false)
            }
        }
        .padding(16)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 380, idealHeight: 520)
        .task(id: matchRequestID) {
            liveMatchCount = nil
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, ruleSet.validationErrors.isEmpty else { return }
            liveMatchCount = ruleSet.filter(librarySnapshots.snapshot.tracks).count
        }
    }

    private func valuePrompt(for field: SmartField) -> String {
        field.isDate ? "Days ago" : "Value"
    }

    private func save() -> Bool {
        do {
            let data = try ruleSet.encode()
            let saved: Playlist
            if let existingTarget {
                let existing = try existingTarget.resolveRequired(in: modelContext)
                existing.name = trimmedName
                existing.smartPlaylist = true
                existing.smartPlaylistRules = data
                existing.dateModified = Date()
                saved = existing
            } else {
                let playlist = Playlist(name: trimmedName, smart: true)
                playlist.smartPlaylistRules = data
                modelContext.insert(playlist)
                saved = playlist
            }
            try modelContext.save()
            onSavedModel?(saved)
            onSavedID?(saved.id)
            return true
        } catch let error as SmartPlaylistEditorTargetResolutionError {
            LibraryStatus.shared.showNotice(
                error.localizedDescription,
                severity: .warning
            )
            return false
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError(
                "Could not save the smart playlist: \(error.localizedDescription)"
            )
            return false
        }
    }
}
