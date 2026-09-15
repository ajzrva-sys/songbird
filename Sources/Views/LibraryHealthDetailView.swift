import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Shared detail surface for catalog-backed Library Health checks.
/// Findings and their underlying tracks share one stable-ID selection/action model.
public struct LibraryHealthDetailView: View {
    public let category: LibraryHealthCategory

    @EnvironmentObject private var health: LibraryHealthProjectionStore
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var checkedProposalIDs: Set<UUID> = []
    @State private var selectedCandidates: [UUID: String] = [:]
    @State private var initializedPlanID: UUID?
    @State private var confirmsApply = false
    @State private var confirmsRelocation = false
    @State private var confirmsRemoval = false
    @State private var selectedRelocationTrackIDs: Set<UUID> = []
    @State private var selectedRemovalTrackIDs: Set<UUID> = []
    @State private var selectedArtworkGroupIDs: Set<String> = []
    @State private var selectedArtworkPaths: [String: String] = [:]
    @State private var isApplying = false
    @State private var notice: String?
    @State private var errorMessage: String?
    @State private var summaryOwner = LibraryContentSummaryOwner()

    public init(category: LibraryHealthCategory) {
        self.category = category
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .onAppear {
            LibraryStatus.shared.summary.activate(owner: summaryOwner, initial: detailSummary)
        }
        .onDisappear { LibraryStatus.shared.summary.clear(owner: summaryOwner) }
        .task {
            if category.isFileAvailabilityCheck {
                health.observe(category: category)
            } else {
                health.check(category: category)
            }
        }
        .task(id: detailSummary) {
            LibraryStatus.shared.summary.update(owner: summaryOwner, summary: detailSummary)
        }
        .onChange(of: currentPlan?.id) { _, _ in initializePlan() }
        .alert("Apply Library Health Changes?", isPresented: $confirmsApply) {
            Button("Cancel", role: .cancel) {}
            Button("Apply \(selectedChanges.count)") { applySelection() }
        } message: {
            Text("Songbird will update the checked findings in one catalog transaction. Audio files and their tags are not changed.")
        }
        .alert("Relocate Missing Library Records?", isPresented: $confirmsRelocation) {
            Button("Cancel", role: .cancel) {}
            Button("Relocate \(selectedRelocationTrackIDs.count)") { applyRelocations() }
        } message: {
            Text("Songbird will update only the selected catalog paths. Audio files and their tags are not moved or changed.")
        }
        .alert("Remove Missing Records from Catalog?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove \(selectedRemovalTrackIDs.count) from Catalog", role: .destructive) {
                removeMissingRecords()
            }
        } message: {
            Text("This removes only Songbird's catalog records. Audio files are never deleted or moved, and Undo remains available until the next Health change.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName).font(.title2.weight(.semibold))
                    if let result = state.lastGood {
                        Text("\(result.findingCount) finding\(result.findingCount == 1 ? "" : "s") · \(result.affectedTrackCount) affected track\(result.affectedTrackCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if case .checking = state { ProgressView().controlSize(.small) }
            }
            HStack {
                if hasApplicableProposals {
                    Button("Apply \(checkedProposalIDs.count) Checked…") { confirmsApply = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedChanges.isEmpty || isApplying)
                }
                if showsHeaderCheckButton {
                    Button(checkButtonLabel) {
                        if category.isFileAvailabilityCheck {
                            health.check(category: category)
                        } else {
                            health.rescanLocalEvidence(category: category)
                        }
                    }
                    .disabled(isApplying || isChecking)
                }
                if isChecking {
                    Button("Cancel") { health.cancel(category: category) }
                }
                Spacer()
            }
            if isChecking, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total)) {
                    Text("Checking local evidence… \(progress.completed) of \(progress.total)")
                        .font(.caption)
                }
            }
            if let notice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(notice)
                    if actions.healthUndoAvailable {
                        Button("Undo") { undo() }.disabled(isApplying)
                    }
                }
                .font(.callout)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .notChecked:
            ContentUnavailableView {
                Label("Not Checked", systemImage: "clock")
            } description: {
                Text("Run this check to inspect the current disposable catalog snapshot.")
            } actions: {
                Button("Check Now") { health.check(category: category) }
            }
        case .checking(let lastGood):
            if let lastGood { resultContent(lastGood, isStale: true) }
            else { ProgressView("Checking library…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        case .ready(let result):
            resultContent(result, isStale: false)
        case .stale(let lastGood):
            resultContent(lastGood, isStale: true)
        case .failed(let message, let lastGood):
            if let lastGood {
                resultContent(lastGood, isStale: true)
                    .overlay(alignment: .topTrailing) {
                        Button("Retry") { health.retry(category: category) }
                            .help(message)
                            .padding(8)
                    }
            } else {
                ContentUnavailableView {
                    Label("Check Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { health.retry(category: category) }
                }
            }
        }
    }

    private func resultContent(_ result: LibraryHealthCategoryResult, isStale: Bool) -> some View {
        Group {
            if result.findingCount == 0 {
                ContentUnavailableView(
                    "No \(category.displayName)",
                    systemImage: "checkmark.circle",
                    description: Text("This check found no problems in the current library view.")
                )
            } else if let plan = result.remediationPlan {
                VStack(spacing: 0) {
                    if isStale {
                        Label("Showing the last successful results while this check refreshes.", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(plan.proposals) { proposal in proposalRow(proposal) }
                        }
                        .padding(12)
                    }
                    .frame(minHeight: 150, idealHeight: 230, maxHeight: 300)
                    Divider()
                    TrackTableView(
                        title: "Affected Tracks",
                        collection: .orderedTrackIDs(result.affectedTrackIDs),
                        showsFilters: false,
                        showsHeader: false,
                        supportsSearch: true,
                        emptyMessage: "No Matching Findings",
                        emptyHint: "Clear search to show affected tracks",
                        publishesSummary: false
                    )
                }
            } else if let report = result.fileReport {
                fileReportContent(
                    report,
                    sourceRevision: result.sourceRevision,
                    isStale: isStale
                )
            } else if let report = result.artworkReport {
                artworkReportContent(report, isStale: isStale)
            }
        }
    }

    private func artworkReportContent(
        _ report: LibraryArtworkHealthReport,
        isStale: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if isStale {
                Label("Showing the last successful results while the catalog refreshes.", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            HStack {
                Button("Find Local Artwork") {
                    health.rescanLocalEvidence(category: .missingArtwork)
                }
                Button("Apply \(applicableArtworkFindings(in: report).count) Selected…") {
                    applyLocalArtwork(from: report)
                }
                .buttonStyle(.borderedProminent)
                .disabled(applicableArtworkFindings(in: report).isEmpty || isStale || isApplying)
                Button("Review Selected on Discogs…") {
                    let albumIDs = Set(report.findings.filter {
                        selectedArtworkGroupIDs.contains($0.groupID)
                    }.flatMap(\.albumIDs))
                    guard albumIDs.isEmpty == false else { return }
                    DiscogsBulkReviewWindowPresenter.show(
                        modelContext: modelContext,
                        albumIDs: albumIDs,
                        actions: actions
                    )
                }
                .disabled(selectedArtworkGroupIDs.isEmpty || isApplying)
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(report.findings) { finding in
                        artworkRow(finding)
                    }
                }
                .padding(12)
            }
        }
        .onAppear { initializeArtworkSelection(report) }
        .onChange(of: report) { _, updated in initializeArtworkSelection(updated) }
    }

    private func artworkRow(_ finding: LibraryArtworkHealthFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selectedArtworkGroupIDs.contains(finding.groupID) },
                set: { selected in
                    if selected { selectedArtworkGroupIDs.insert(finding.groupID) }
                    else { selectedArtworkGroupIDs.remove(finding.groupID) }
                }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title).font(.headline)
                Text("\(finding.artist) · \(finding.trackIDs.count) track\(finding.trackIDs.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                if finding.localCandidatePaths.isEmpty {
                    Text("Unresolved · no reviewed local image candidate")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Local artwork", selection: Binding(
                        get: { selectedArtworkPaths[finding.groupID] ?? finding.localCandidatePaths[0] },
                        set: { selectedArtworkPaths[finding.groupID] = $0 }
                    )) {
                        ForEach(finding.localCandidatePaths, id: \.self) {
                            Text(URL(fileURLWithPath: $0).lastPathComponent).tag($0)
                        }
                    }
                    .frame(maxWidth: 280)
                    Text("Review required · local file beside this album")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Choose Image…") { chooseArtwork(for: finding) }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func initializeArtworkSelection(_ report: LibraryArtworkHealthReport) {
        let valid = Set(report.findings.map(\.groupID))
        selectedArtworkGroupIDs.formIntersection(valid)
        for finding in report.findings where selectedArtworkPaths[finding.groupID] == nil {
            selectedArtworkPaths[finding.groupID] = finding.localCandidatePaths.first
        }
    }

    private func applicableArtworkFindings(
        in report: LibraryArtworkHealthReport
    ) -> [LibraryArtworkHealthFinding] {
        report.findings.filter {
            selectedArtworkGroupIDs.contains($0.groupID)
                && selectedArtworkPaths[$0.groupID] != nil
        }
    }

    private func applyLocalArtwork(from report: LibraryArtworkHealthReport) {
        let findings = applicableArtworkFindings(in: report)
        isApplying = true
        errorMessage = nil
        Task {
            do {
                var changes: [LibraryArtworkChange] = []
                for finding in findings {
                    try Task.checkCancellation()
                    guard let path = selectedArtworkPaths[finding.groupID] else { continue }
                    let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                    changes.append(contentsOf: finding.albumIDs.map {
                        LibraryArtworkChange(albumID: $0, expectedArtworkDigest: nil, imageData: data)
                    })
                }
                let result = await actions.applyArtwork(changes)
                isApplying = false
                switch result {
                case .success(let outcome):
                    notice = "Applied artwork to \(outcome.affectedAlbumCount) album\(outcome.affectedAlbumCount == 1 ? "" : "s")."
                    selectedArtworkGroupIDs.removeAll()
                    health.check(category: .missingArtwork)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            } catch {
                isApplying = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseArtwork(for finding: LibraryArtworkHealthFinding) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .gif, .bmp, .webP, .tiff, .heic]
        panel.message = "Choose artwork for \(finding.title)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    let result = await actions.applyArtwork(finding.albumIDs.map {
                        LibraryArtworkChange(albumID: $0, expectedArtworkDigest: nil, imageData: data)
                    })
                    switch result {
                    case .success(let outcome):
                        notice = "Applied artwork to \(outcome.affectedAlbumCount) album\(outcome.affectedAlbumCount == 1 ? "" : "s")."
                        health.check(category: .missingArtwork)
                    case .failure(let error): errorMessage = error.localizedDescription
                    }
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func fileReportContent(
        _ report: LibraryFileHealthReport,
        sourceRevision: Int,
        isStale: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if isStale {
                Label("Showing the last successful results. Choose Check Now to refresh filesystem state.", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            if report.rootFailures.isEmpty == false {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(report.rootFailures) { failure in
                        Label("\(failure.path): \(failure.reason.message)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                Divider()
            }
            if category == .missingFiles {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Relocation Review").font(.headline)
                        Spacer()
                        Button("Relocate \(selectedRelocationTrackIDs.count) Selected…") {
                            confirmsRelocation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedRelocationTrackIDs.isEmpty || isStale || isApplying)
                        Button("Remove \(selectedRemovalTrackIDs.count) from Catalog…", role: .destructive) {
                            confirmsRemoval = true
                        }
                        .disabled(selectedRemovalTrackIDs.isEmpty || isStale || isApplying)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(report.findings) { finding in
                                relocationRow(finding)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxHeight: 260, alignment: .top)
                Divider()
            } else if category == .unavailableVolumes {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(report.findings) { finding in
                            if case .unavailable(let reason) = finding.status {
                                Label(reason.message, systemImage: "externaldrive.badge.exclamationmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 150)
                Divider()
            }
            TrackTableView(
                title: "Affected Tracks",
                collection: .orderedTrackIDs(report.affectedTrackIDs),
                showsFilters: false,
                showsHeader: false,
                supportsSearch: true,
                emptyMessage: "No Matching Findings",
                emptyHint: "Clear search to show affected tracks",
                publishesSummary: false
            )
        }
        .onAppear { initializeRelocationSelection(report) }
        .onChange(of: report) { _, updated in initializeRelocationSelection(updated) }
    }

    private func relocationRow(_ finding: LibraryFileHealthFinding) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selectedRelocationTrackIDs.contains(finding.trackID) },
                set: { selected in
                    if selected { selectedRelocationTrackIDs.insert(finding.trackID) }
                    else { selectedRelocationTrackIDs.remove(finding.trackID) }
                }
            ))
            .labelsHidden()
            .disabled(finding.relocationCandidates.count != 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: finding.expectedPath).lastPathComponent)
                    .font(.callout.weight(.semibold))
                Text(finding.expectedPath).font(.caption).foregroundStyle(.secondary)
                if finding.relocationCandidates.count == 1,
                   let candidate = finding.relocationCandidates.first {
                    Label(candidate.path, systemImage: "arrow.turn.down.right")
                        .font(.caption)
                    Text(candidate.checksumMatchesCatalog
                         ? "Review required · local checksum matches the catalog"
                         : "Review required · unique filename match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if finding.relocationCandidates.isEmpty {
                    Text("Unresolved · no configured root contains this filename")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Unresolved · \(finding.relocationCandidates.count) possible matches")
                        .font(.caption).foregroundStyle(.orange)
                    ForEach(finding.relocationCandidates) { candidate in
                        Text(candidate.path).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Toggle("Remove", isOn: Binding(
                get: { selectedRemovalTrackIDs.contains(finding.trackID) },
                set: { selected in
                    if selected { selectedRemovalTrackIDs.insert(finding.trackID) }
                    else { selectedRemovalTrackIDs.remove(finding.trackID) }
                }
            ))
            .toggleStyle(.checkbox)
            .help("Select this missing record for catalog-only removal")
        }
    }

    private func initializeRelocationSelection(_ report: LibraryFileHealthReport) {
        let applicable = Set(report.findings.filter {
            $0.relocationCandidates.count == 1
        }.map(\.trackID))
        selectedRelocationTrackIDs.formIntersection(applicable)
        selectedRemovalTrackIDs.formIntersection(Set(report.findings.map(\.trackID)))
    }

    private func applyRelocations() {
        guard let result = state.lastGood,
              let report = result.fileReport else { return }
        let changes = report.findings.compactMap { finding -> LibraryPathChange? in
            guard selectedRelocationTrackIDs.contains(finding.trackID),
                  finding.relocationCandidates.count == 1,
                  let candidate = finding.relocationCandidates.first else { return nil }
            return LibraryPathChange(
                trackID: finding.trackID,
                expectedOldPath: finding.expectedPath,
                candidatePath: candidate.path,
                expectedCandidateChecksum: candidate.checksum,
                sourceRevision: result.sourceRevision
            )
        }
        isApplying = true
        errorMessage = nil
        Task { @MainActor in
            let outcome = await actions.applyMissingFileRelocations(changes)
            isApplying = false
            switch outcome {
            case .success(let result):
                selectedRelocationTrackIDs.removeAll()
                notice = "Relocated \(result.affectedTrackCount) catalog record\(result.affectedTrackCount == 1 ? "" : "s")."
                health.check(category: category)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeMissingRecords() {
        guard let result = state.lastGood,
              let report = result.fileReport else { return }
        let removals = report.findings.compactMap { finding -> LibraryMissingRecordRemoval? in
            guard selectedRemovalTrackIDs.contains(finding.trackID),
                  case .missing = finding.status else { return nil }
            return LibraryMissingRecordRemoval(
                trackID: finding.trackID,
                expectedPath: finding.expectedPath,
                sourceRevision: result.sourceRevision
            )
        }
        isApplying = true
        errorMessage = nil
        Task { @MainActor in
            let outcome = await actions.removeMissingCatalogRecords(removals)
            isApplying = false
            switch outcome {
            case .success(let result):
                selectedRemovalTrackIDs.removeAll()
                notice = "Removed \(result.affectedTrackCount) missing record\(result.affectedTrackCount == 1 ? "" : "s") from the catalog. Files were not changed."
                health.check(category: category)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func proposalRow(_ proposal: LibraryRemediationProposal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: checkedBinding(proposal))
                .labelsHidden()
                .disabled(!proposal.isApplicable)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(proposal.issue.grouping.displayName).font(.headline)
                    Text("\(proposal.affectedTrackCount) track\(proposal.affectedTrackCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(confidenceLabel(proposal.confidence))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(proposal.confidence == .automaticSafe ? .green : .secondary)
                }
                HStack(spacing: 6) {
                    Text(proposal.issue.currentValue).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    if proposal.candidateValues.count > 1 {
                        Picker("Canonical value", selection: candidateBinding(proposal)) {
                            ForEach(proposal.candidateValues, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    } else {
                        Text(proposal.proposedValue ?? "No applicable suggestion")
                    }
                }
                .font(.callout)
                ForEach(proposal.evidence) { Text($0.summary).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var state: LibraryHealthCheckState { health.state(for: category) }
    private var detailSummary: LibraryContentSummary {
        guard let result = state.lastGood else { return .none }
        return .healthDetail(
            findingCount: result.findingCount,
            affectedTrackCount: result.affectedTrackCount
        )
    }
    private var progress: LibraryHealthCheckProgress { health.progress(for: category) }
    private var currentPlan: LibraryRemediationPlan? { state.lastGood?.remediationPlan }
    private var checkButtonLabel: String {
        if category.isFileAvailabilityCheck { return "Check Now" }
        return category == .lowBitrate ? "Refresh" : "Rescan Local Evidence"
    }
    private var showsHeaderCheckButton: Bool {
        category.isFileAvailabilityCheck == false || state.lastGood != nil || isChecking
    }
    private var isChecking: Bool { if case .checking = state { true } else { false } }
    private var hasApplicableProposals: Bool { currentPlan?.proposals.contains(where: \.isApplicable) == true }
    private var selectedChanges: [LibraryRemediationChange] { selectedPlan?.changes ?? [] }
    private var selectedPlan: LibraryRemediationPlan? {
        guard let plan = currentPlan else { return nil }
        let proposals = plan.proposals.compactMap { proposal -> LibraryRemediationProposal? in
            guard checkedProposalIDs.contains(proposal.id), proposal.isApplicable else { return nil }
            return selectedCandidates[proposal.id].map(proposal.choosing) ?? proposal
        }
        return LibraryRemediationPlan(category: category, createdAt: plan.createdAt, proposals: proposals)
    }

    private func initializePlan() {
        guard let plan = currentPlan, initializedPlanID != plan.id else { return }
        initializedPlanID = plan.id
        checkedProposalIDs = Set(plan.proposals.filter(\.beginsChecked).map(\.id))
        selectedCandidates = Dictionary(uniqueKeysWithValues: plan.proposals.compactMap { proposal in
            proposal.proposedValue.map { (proposal.id, $0) }
        })
    }

    private func checkedBinding(_ proposal: LibraryRemediationProposal) -> Binding<Bool> {
        Binding(
            get: { checkedProposalIDs.contains(proposal.id) },
            set: { checked in
                if checked { checkedProposalIDs.insert(proposal.id) }
                else { checkedProposalIDs.remove(proposal.id) }
            }
        )
    }

    private func candidateBinding(_ proposal: LibraryRemediationProposal) -> Binding<String> {
        Binding(
            get: { selectedCandidates[proposal.id] ?? proposal.proposedValue ?? "" },
            set: { selectedCandidates[proposal.id] = $0 }
        )
    }

    private func confidenceLabel(_ confidence: LibraryRemediationConfidence) -> String {
        switch confidence {
        case .automaticSafe: "Safe"
        case .reviewRequired: "Review required"
        case .unresolved: "Unresolved"
        }
    }

    private func applySelection() {
        guard let selectedPlan else { return }
        isApplying = true
        errorMessage = nil
        Task { @MainActor in
            let result = await actions.applyHealthPlan(selectedPlan)
            isApplying = false
            switch result {
            case .success(let outcome):
                notice = "Updated \(outcome.affectedTrackCount) track\(outcome.affectedTrackCount == 1 ? "" : "s")."
                health.check(category: category)
            case .failure(let error): errorMessage = error.localizedDescription
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
                if outcome.affectedAlbumCount > 0 {
                    notice = "Restored artwork for \(outcome.affectedAlbumCount) album\(outcome.affectedAlbumCount == 1 ? "" : "s")."
                } else {
                    notice = "Restored \(outcome.affectedTrackCount) track\(outcome.affectedTrackCount == 1 ? "" : "s")."
                }
                health.check(category: category)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }
}
