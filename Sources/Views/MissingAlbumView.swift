import SwiftUI

/// Relationship-aware Library Health detail for tracks with no meaningful album name.
public struct MissingAlbumView: View {
    @EnvironmentObject private var health: LibraryHealthProjectionStore
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @Environment(\.colorScheme) private var colorScheme
    @State private var checkedProposalIDs: Set<UUID> = []
    @State private var initializedPlanID: UUID?
    @State private var confirmsSafeApply = false
    @State private var showsReview = false
    @State private var isApplying = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var summaryOwner = LibraryContentSummaryOwner()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stateContent
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .onAppear {
            LibraryStatus.shared.summary.activate(owner: summaryOwner, initial: detailSummary)
        }
        .onDisappear { LibraryStatus.shared.summary.clear(owner: summaryOwner) }
        .task { health.check(category: .missingAlbumNames) }
        .task(id: detailSummary) {
            LibraryStatus.shared.summary.update(owner: summaryOwner, summary: detailSummary)
        }
        .onChange(of: currentPlan?.id) { _, _ in initializeCheckedState() }
        .alert("Apply Safe Album Suggestions?", isPresented: $confirmsSafeApply) {
            Button("Cancel", role: .cancel) {}
            Button("Apply \(safeSelectionCount)") { applySafeSuggestions() }
        } message: {
            Text("Songbird will update \(safeAffectedTrackCount) track\(safeAffectedTrackCount == 1 ? "" : "s") using only the checked deterministic local evidence.")
        }
        .sheet(isPresented: $showsReview) {
            if let plan = currentPlan {
                MissingAlbumReviewSheet(
                    plan: plan,
                    isApplying: isApplying,
                    apply: applyReviewedSuggestions
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missing Album Names")
                        .font(.title2.weight(.semibold))
                    if let plan = currentPlan {
                        Text("\(plan.proposals.count) finding\(plan.proposals.count == 1 ? "" : "s") · \(affectedTrackIDs.count) affected tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if case .checking = healthState {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack {
                Button("Apply \(safeSelectionCount) Safe Suggestions…") {
                    confirmsSafeApply = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(safeSelectionCount == 0 || isApplying)

                Button("Review Unresolved") { showsReview = true }
                    .disabled(reviewableCount == 0 || isApplying)

                Button("Rescan Local Evidence") {
                    health.rescanLocalEvidence(category: .missingAlbumNames)
                }
                    .disabled(isApplying || isChecking)

                if isChecking {
                    Button("Cancel") { health.cancel(category: .missingAlbumNames) }
                }
                Spacer()
            }

            if let resultMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(resultMessage)
                    if actions.healthUndoAvailable {
                        Button("Undo") { undo() }
                            .disabled(isApplying)
                    }
                }
                .font(.callout)
            }
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(errorMessage)
                    if case .failed = healthState {
                        Button("Retry") { health.retry(category: .missingAlbumNames) }
                    }
                }
                .font(.callout)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch healthState {
        case .notChecked:
            ProgressView("Checking library metadata…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .checking(let lastGood):
            if let plan = lastGood?.remediationPlan {
                planContent(plan, isStale: true)
            } else {
                ProgressView("Checking library metadata…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .ready(let result):
            if let plan = result.remediationPlan {
                planContent(plan, isStale: false)
            }
        case .stale(let lastGood):
            if let plan = lastGood.remediationPlan {
                planContent(plan, isStale: true)
            }
        case .failed(let message, let lastGood):
            if let plan = lastGood?.remediationPlan {
                planContent(plan, isStale: true)
                    .onAppear { errorMessage = message }
            } else {
                ContentUnavailableView {
                    Label("Album Check Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { health.retry(category: .missingAlbumNames) }
                }
            }
        }
    }

    @ViewBuilder
    private func planContent(_ plan: LibraryRemediationPlan, isStale: Bool) -> some View {
        if plan.proposals.isEmpty {
            ContentUnavailableView(
                "No Missing Album Names",
                systemImage: "checkmark.circle",
                description: Text("All library tracks have a meaningful album name.")
            )
        } else {
            VStack(spacing: 0) {
                if isStale {
                    Label("Showing the last successful results while Songbird refreshes them.", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(plan.proposals) { proposal in
                            proposalRow(proposal)
                        }
                    }
                    .padding(12)
                }
                .frame(minHeight: 150, idealHeight: 230, maxHeight: 280)
                Divider()
                TrackTableView(
                    title: "Affected Tracks",
                    collection: .orderedTrackIDs(affectedTrackIDs),
                    showsFilters: false,
                    showsHeader: false,
                    supportsSearch: true,
                    emptyMessage: "No Affected Tracks",
                    emptyHint: "Refresh Library Health to check again",
                    publishesSummary: false
                )
            }
        }
    }

    private func proposalRow(_ proposal: LibraryRemediationProposal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { checkedProposalIDs.contains(proposal.id) },
                set: { checked in
                    if checked { checkedProposalIDs.insert(proposal.id) }
                    else { checkedProposalIDs.remove(proposal.id) }
                }
            ))
            .labelsHidden()
            .disabled(proposal.confidence != .automaticSafe || !proposal.isApplicable)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(proposal.issue.grouping.displayName)
                        .font(.headline)
                    Text("\(proposal.affectedTrackCount) track\(proposal.affectedTrackCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(confidenceLabel(proposal.confidence))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(confidenceColor(proposal.confidence))
                }
                HStack(spacing: 6) {
                    Text(proposal.issue.currentValue).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Text(proposal.proposedValue ?? "No suggestion")
                        .fontWeight(proposal.proposedValue == nil ? .regular : .medium)
                }
                .font(.callout)
                ForEach(proposal.evidence) { evidence in
                    Text(evidence.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var healthState: LibraryHealthCheckState {
        health.state(for: .missingAlbumNames)
    }
    private var detailSummary: LibraryContentSummary {
        guard let result = healthState.lastGood else { return .none }
        return .healthDetail(
            findingCount: result.findingCount,
            affectedTrackCount: result.affectedTrackCount
        )
    }
    private var currentPlan: LibraryRemediationPlan? { healthState.lastGood?.remediationPlan }
    private var isChecking: Bool { if case .checking = healthState { true } else { false } }
    private var affectedTrackIDs: [UUID] {
        var seen: Set<UUID> = []
        return currentPlan?.proposals.flatMap(\.issue.grouping.trackIDs).filter {
            seen.insert($0).inserted
        } ?? []
    }
    private var safeSelection: Set<UUID> {
        Set(currentPlan?.proposals.filter {
            $0.confidence == .automaticSafe && checkedProposalIDs.contains($0.id)
        }.map(\.id) ?? [])
    }
    private var safeSelectionCount: Int { safeSelection.count }
    private var safeAffectedTrackCount: Int {
        currentPlan?.proposals.filter { safeSelection.contains($0.id) }
            .reduce(0) { $0 + $1.affectedTrackCount } ?? 0
    }
    private var reviewableCount: Int {
        currentPlan?.proposals.filter { $0.confidence != .automaticSafe }.count ?? 0
    }

    private func initializeCheckedState() {
        guard let plan = currentPlan, initializedPlanID != plan.id else { return }
        initializedPlanID = plan.id
        checkedProposalIDs = Set(plan.proposals.filter(\.beginsChecked).map(\.id))
    }

    private func applySafeSuggestions() {
        guard let plan = currentPlan else { return }
        apply(plan.selecting(safeSelection))
    }

    private func applyReviewedSuggestions(_ proposalIDs: Set<UUID>) {
        guard let plan = currentPlan else { return }
        showsReview = false
        apply(plan.selecting(proposalIDs))
    }

    private func apply(_ plan: LibraryRemediationPlan) {
        isApplying = true
        errorMessage = nil
        Task { @MainActor in
            let result = await actions.applyHealthPlan(plan)
            isApplying = false
            switch result {
            case .success(let outcome):
                resultMessage = "Updated \(outcome.affectedTrackCount) track\(outcome.affectedTrackCount == 1 ? "" : "s")."
                health.check(category: .missingAlbumNames)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func undo() {
        isApplying = true
        errorMessage = nil
        Task { @MainActor in
            let result = await actions.undoLatestHealthMutation()
            isApplying = false
            switch result {
            case .success(let outcome):
                resultMessage = "Restored \(outcome.affectedTrackCount) track\(outcome.affectedTrackCount == 1 ? "" : "s")."
                health.check(category: .missingAlbumNames)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func confidenceLabel(_ confidence: LibraryRemediationConfidence) -> String {
        switch confidence {
        case .automaticSafe: "Safe"
        case .reviewRequired: "Review required"
        case .unresolved: "Unresolved"
        }
    }

    private func confidenceColor(_ confidence: LibraryRemediationConfidence) -> Color {
        switch confidence {
        case .automaticSafe: .green
        case .reviewRequired: .orange
        case .unresolved: .secondary
        }
    }
}

private struct MissingAlbumReviewSheet: View {
    let plan: LibraryRemediationPlan
    let isApplying: Bool
    let apply: (Set<UUID>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review Album Suggestions").font(.title2.weight(.semibold))
                Text("Folder-name suggestions require your confirmation. Conflicting or missing evidence stays visible but cannot be applied.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            Divider()
            List(plan.proposals.filter { $0.confidence != .automaticSafe }) { proposal in
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { selection.contains(proposal.id) },
                        set: { checked in
                            if checked { selection.insert(proposal.id) }
                            else { selection.remove(proposal.id) }
                        }
                    ))
                    .labelsHidden()
                    .disabled(!proposal.isApplicable)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(proposal.issue.grouping.displayName).font(.headline)
                        Text("Unknown Album → \(proposal.proposedValue ?? "No suggestion")")
                        Text(proposal.evidence.map(\.summary).joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(proposal.affectedTrackCount) tracks").font(.caption)
                }
                .padding(.vertical, 4)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply Selected") { apply(selection) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty || isApplying)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 430)
    }
}
