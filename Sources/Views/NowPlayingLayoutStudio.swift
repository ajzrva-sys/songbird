import SwiftUI

/// Floating inspector shown while Edit Layout mode is active.
struct NowPlayingLayoutStudio: View {
    @Binding var itemOrder: [PlayerToolbarItem]
    @Binding var selectedZone: LayoutStudioZone
    @Binding var faceplateWidth: Double
    @Binding var faceplateHeight: Double
    @Binding var leadingGap: Double
    @Binding var trailingGap: Double
    var leadingGapRange: ClosedRange<Double>
    var trailingGapRange: ClosedRange<Double>
    @Binding var barPadding: Double
    @Binding var buttonSpacing: Double
    @Binding var controlsSpacing: Double
    var onDone: () -> Void
    var onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Layout Studio")
                        .font(.headline)
                    Text("Drag items directly on the player bar. Use the controls below for precise sizing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset") { onReset() }
                    .buttonStyle(.bordered)
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            Label("Grab the outlined Now Playing box and drop it wherever you want.", systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(.secondary)

            presetPicker
            customizationLane
            zoneMap
            zoneControls
            Divider()

            HStack {
                Text("Available Items")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("The bar keeps its current appearance until you move something.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            palette
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.35))
                .frame(height: 1)
        }
    }

    private var currentPreset: NowPlayingLayoutPreset? {
        NowPlayingLayoutPreset.match(
            faceplateWidth: faceplateWidth,
            faceplateHeight: faceplateHeight,
            leadingGap: leadingGap,
            trailingGap: trailingGap,
            barPadding: barPadding,
            buttonSpacing: buttonSpacing,
            controlsSpacing: controlsSpacing
        )
    }

    private var presetPicker: some View {
        HStack(spacing: 8) {
            Text("Preset")
                .font(.caption.weight(.medium))
            ForEach(NowPlayingLayoutPreset.allCases) { preset in
                Button(preset.displayName) {
                    applyPreset(preset)
                }
                .buttonStyle(.bordered)
                .tint(currentPreset == preset ? .accentColor : .secondary)
            }
            if currentPreset == nil {
                Text("Custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyPreset(_ preset: NowPlayingLayoutPreset) {
        let config = preset.configuration
        faceplateWidth = config.faceplateWidth
        faceplateHeight = config.faceplateHeight
        leadingGap = config.leadingGap
        trailingGap = config.trailingGap
        barPadding = config.barPadding
        buttonSpacing = config.buttonSpacing
        controlsSpacing = config.controlsSpacing
    }

    private var customizationLane: some View {
        HStack(spacing: 8) {
            ForEach(itemOrder) { item in
                toolbarChip(item, removable: item != .faceplate)
                    .draggable(item.rawValue)
                    .dropDestination(for: String.self) { values, _ in
                        guard let raw = values.first,
                              let dragged = PlayerToolbarItem(rawValue: raw) else { return false }
                        move(dragged, before: item)
                        return true
                    }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first,
                  let dragged = PlayerToolbarItem(rawValue: raw) else { return false }
            append(dragged)
            return true
        }
    }

    private var palette: some View {
        HStack(spacing: 8) {
            ForEach(PlayerToolbarItem.allCases.filter { !itemOrder.contains($0) }) { item in
                toolbarChip(item, removable: false)
                    .draggable(item.rawValue)
            }
            if PlayerToolbarItem.allCases.allSatisfy(itemOrder.contains) {
                Text("All items are in the player bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 32)
    }

    private func toolbarChip(_ item: PlayerToolbarItem, removable: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .frame(width: 16)
            Text(item.title)
                .lineLimit(1)
            if removable {
                Menu {
                    Button("Move Left") { move(item, offset: -1) }
                        .disabled(itemOrder.first == item)
                    Button("Move Right") { move(item, offset: 1) }
                        .disabled(itemOrder.last == item)
                    Divider()
                    Button("Remove", role: .destructive) {
                        itemOrder.removeAll { $0 == item }
                    }
                } label: {
                    Label("Actions for \(item.title)", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            } else if item != .faceplate {
                Button("Add \(item.title)", systemImage: "plus.circle") {
                    append(item)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private func append(_ item: PlayerToolbarItem) {
        itemOrder.removeAll { $0 == item }
        itemOrder.append(item)
    }

    private func move(_ dragged: PlayerToolbarItem, before target: PlayerToolbarItem) {
        guard dragged != target else { return }
        itemOrder.removeAll { $0 == dragged }
        guard let targetIndex = itemOrder.firstIndex(of: target) else {
            itemOrder.append(dragged)
            return
        }
        itemOrder.insert(dragged, at: targetIndex)
    }

    private func move(_ item: PlayerToolbarItem, offset: Int) {
        guard let source = itemOrder.firstIndex(of: item) else { return }
        let destination = min(max(source + offset, 0), itemOrder.count - 1)
        guard source != destination else { return }
        itemOrder.remove(at: source)
        itemOrder.insert(item, at: destination)
    }

    // MARK: - Zone map

    private var zoneMap: some View {
        HStack(spacing: 6) {
            zoneChip(.controlsSpacing, label: "Controls")
            zoneChip(.buttonSpacing, label: "Buttons", narrow: true)
            zoneChip(.leadingGap, label: "Gap", narrow: true)
            zoneChip(.faceplate, label: "Now Playing")
            zoneChip(.trailingGap, label: "Gap", narrow: true)
            zoneChip(.barPadding, label: "Pad", narrow: true)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func zoneChip(_ zone: LayoutStudioZone, label: String, narrow: Bool = false) -> some View {
        let selected = selectedZone == zone
        return Button {
            selectedZone = zone
        } label: {
            Text(label)
                .font(.caption2.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(minWidth: narrow ? 36 : 64)
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls

    @ViewBuilder
    private var zoneControls: some View {
        switch selectedZone {
        case .faceplate:
            studioStepper(
                title: "Width",
                value: $faceplateWidth,
                range: NowPlayingLayoutSettings.faceplateWidthRange,
                step: NowPlayingLayoutSettings.widthStep
            )
            studioStepper(
                title: "Height",
                value: $faceplateHeight,
                range: NowPlayingLayoutSettings.faceplateHeightRange,
                step: NowPlayingLayoutSettings.heightStep
            )
        case .leadingGap:
            studioStepper(
                title: "Controls → Now Playing",
                value: $leadingGap,
                range: leadingGapRange,
                step: NowPlayingLayoutSettings.spacingStep
            )
        case .trailingGap:
            studioStepper(
                title: "Now Playing → Right Edge",
                value: $trailingGap,
                range: trailingGapRange,
                step: NowPlayingLayoutSettings.spacingStep
            )
        case .buttonSpacing:
            studioStepper(
                title: "Button Spacing",
                value: $buttonSpacing,
                range: NowPlayingLayoutSettings.buttonSpacingRange,
                step: NowPlayingLayoutSettings.buttonSpacingStep
            )
        case .controlsSpacing:
            studioStepper(
                title: "Group Spacing",
                value: $controlsSpacing,
                range: NowPlayingLayoutSettings.controlsSpacingRange,
                step: NowPlayingLayoutSettings.controlsSpacingStep
            )
        case .barPadding:
            studioStepper(
                title: "Bar Padding",
                value: $barPadding,
                range: NowPlayingLayoutSettings.barPaddingRange,
                step: NowPlayingLayoutSettings.spacingStep
            )
        }
    }

    private func studioStepper(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        // SwiftUI's Slider traps when a dynamic range is narrower than its
        // stride (for example 0...0.4 with a 1 pt step). Quantize first and
        // never expose an out-of-range value to Slider or Stepper.
        let stepCount = floor((range.upperBound - range.lowerBound) / step)
        let usableUpperBound = range.lowerBound + max(0, stepCount) * step
        let controlRange = range.lowerBound...usableUpperBound
        let hasAdjustableRange = usableUpperBound - range.lowerBound >= step
        let safeValue = Binding<Double>(
            get: {
                NowPlayingLayoutSettings.clamp(value.wrappedValue, to: controlRange)
            },
            set: {
                value.wrappedValue = NowPlayingLayoutSettings.clamp($0, to: controlRange)
            }
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                TextField(
                    "",
                    value: safeValue,
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)

                if hasAdjustableRange {
                    Stepper(
                        "",
                        value: safeValue,
                        in: controlRange,
                        step: step
                    )
                    .labelsHidden()
                }
            }

            if hasAdjustableRange {
                Slider(
                    value: safeValue,
                    in: controlRange,
                    step: step
                )
            } else {
                Text("No additional space is available at this window and faceplate size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Drag handle chrome

struct LayoutDragHandle: View {
    enum Axis { case horizontal, vertical }

    var axis: Axis
    var label: String?
    var isSelected: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.accentColor.opacity(0.45))
                .frame(
                    width: axis == .horizontal ? 10 : 22,
                    height: axis == .horizontal ? 22 : 10
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)

            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.black.opacity(0.72))
                    )
                    .foregroundStyle(.white)
                    .offset(y: axis == .horizontal ? -18 : 16)
            }
        }
        .contentShape(Rectangle().size(CGSize(width: 24, height: 28)))
    }
}

struct LayoutZoneOutline: View {
    var isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.accentColor.opacity(isSelected ? 0.95 : 0.35), lineWidth: isSelected ? 2 : 1)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isSelected ? 0.08 : 0.03))
            )
            .allowsHitTesting(false)
    }
}
