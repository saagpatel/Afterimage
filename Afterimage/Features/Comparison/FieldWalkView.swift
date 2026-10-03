import SwiftUI

struct FieldWalkView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let userPhoto: UIImage
    let candidates: [MatchCandidate]
    let onDismiss: () -> Void

    @State private var selectedCandidateID: String
    @State private var revealFraction: CGFloat = 0.5
    @State private var historicalOffset: CGSize = .zero
    @State private var historicalScale: CGFloat = 1
    @State private var saveMessage: String?
    @State private var savedCandidateID: String?
    @State private var isSaving = false
    @State private var isLineageExpanded = false
    @AccessibilityFocusState private var saveResultFocused: Bool
    @ScaledMetric(relativeTo: .body) private var candidateCardWidth: CGFloat = 176

    init(
        userPhoto: UIImage,
        candidates: [MatchCandidate],
        onDismiss: @escaping () -> Void
    ) {
        self.userPhoto = userPhoto
        self.candidates = candidates
        self.onDismiss = onDismiss
        _selectedCandidateID = State(initialValue: candidates.first?.id ?? "")
    }

    private var selected: MatchCandidate? {
        candidates.first { $0.id == selectedCandidateID } ?? candidates.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 16) {
                    orientCard
                    candidatePicker
                    if let selected {
                        overlaySection(selected)
                        evidenceCard(selected)
                        provenanceCard(selected)
                        saveSection(selected)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Theme.plate.ignoresSafeArea())
        .onChange(of: selectedCandidateID) { _, _ in
            revealFraction = 0.5
            historicalOffset = .zero
            historicalScale = 1
            saveMessage = nil
            savedCandidateID = nil
            saveResultFocused = false
            isLineageExpanded = false
        }
        .onChange(of: revealFraction) { _, _ in markCompositionChanged() }
        .onChange(of: historicalOffset) { _, _ in markCompositionChanged() }
        .onChange(of: historicalScale) { _, _ in markCompositionChanged() }
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    dismissButton
                    privacySummary(alignment: .leading, textAlignment: .leading)
                }
            } else {
                HStack {
                    dismissButton
                    Spacer()
                    privacySummary(alignment: .trailing, textAlignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                EyebrowText("Field Walk", color: Theme.bone)
            }
            .frame(minHeight: 44)
        }
        .foregroundStyle(Theme.bone)
        .accessibilityLabel("End field walk")
    }

    private func privacySummary(
        alignment: HorizontalAlignment,
        textAlignment: TextAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            EyebrowText("On-device matching", color: Theme.boneMuted)
            Text("Archive images may use archive-host requests")
                .font(.caption2)
                .foregroundStyle(Theme.boneMuted)
                .multilineTextAlignment(textAlignment)
        }
        // Keep this repeated status summary compact; its full wording remains
        // available as one uncapped accessibility label below.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Matching stays on device. Historical images may be fetched from archive hosts. "
                + "Your photo and precise location stay local."
        )
    }

    private var orientCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText("Orient", color: Theme.albumen)
            Text("Hold the view, then inspect the evidence")
                .font(Theme.serifTitle)
                .foregroundStyle(Theme.bone)
            Text("Afterimage will only unlock the overlay when independent signals agree. Missing direction or image evidence stays visible instead of being guessed.")
                .font(.subheadline)
                .foregroundStyle(Theme.boneMuted)
        }
        .instrumentCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var candidatePicker: some View {
        if candidates.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                EyebrowText("Choose a candidate", color: Theme.albumen)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(candidates) { candidate in
                            Button {
                                selectedCandidateID = candidate.id
                            } label: {
                                candidateChip(candidate)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "Candidate \(candidate.photo.title), "
                                    + MatchExplanationPresenter(candidate: candidate).shortLabel
                            )
                            .accessibilityValue(
                                selectedCandidateID == candidate.id ? "Selected" : "Not selected"
                            )
                        }
                    }
                }
            }
            .instrumentCard()
        }
    }

    private func candidateChip(_ candidate: MatchCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = candidate.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .clipped()
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(Theme.plate)
            }
            Text(candidate.photo.title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(candidate.eraLabel ?? "Date unavailable")
                .font(Theme.metaFont)
                .foregroundStyle(Theme.boneMuted)
            Text(MatchExplanationPresenter(candidate: candidate).distanceText + " away")
                .font(Theme.metaFont)
                .foregroundStyle(Theme.boneMuted)
            Text(MatchExplanationPresenter(candidate: candidate).shortLabel)
                .font(Theme.metaFont.weight(.semibold))
                .foregroundStyle(dispositionColor(candidate.confidence.disposition))
        }
        .frame(width: min(candidateCardWidth, 260), alignment: .leading)
        .foregroundStyle(Theme.bone)
        .padding(8)
        .background(Theme.plateRaised)
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    selectedCandidateID == candidate.id ? Theme.albumen : Theme.boneFaint,
                    lineWidth: selectedCandidateID == candidate.id ? 2 : 1
                )
        }
    }

    private func evidenceCard(_ candidate: MatchCandidate) -> some View {
        let presenter = MatchExplanationPresenter(candidate: candidate)
        return VStack(alignment: .leading, spacing: 12) {
            EyebrowText("Why this match", color: Theme.albumen)
            evidenceGroup(
                title: "Supporting",
                symbol: "checkmark.circle.fill",
                color: .green,
                lines: presenter.supporting
            )
            evidenceGroup(
                title: "Contradictory",
                symbol: "exclamationmark.triangle.fill",
                color: Theme.albumen,
                lines: presenter.contradictory
            )
            evidenceGroup(
                title: "Unavailable",
                symbol: "questionmark.circle",
                color: Theme.boneMuted,
                lines: presenter.missing
            )
        }
        .instrumentCard()
        .accessibilityIdentifier("why-this-match")
    }

    @ViewBuilder
    private func evidenceGroup(
        title: String,
        symbol: String,
        color: Color,
        lines: [String]
    ) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                ForEach(lines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.boneMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func overlaySection(_ candidate: MatchCandidate) -> some View {
        if candidate.confidence.mayPresentOverlay,
           let historicalPhoto = candidate.thumbnail {
            VStack(alignment: .leading, spacing: 14) {
                matchSummary(candidate)
                EyebrowText("Compare", color: Theme.albumen)
                Text("Drag the circular divider left or right to compare today with the archive view.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.boneMuted)
                    .fixedSize(horizontal: false, vertical: true)
                SliderOverlayView(
                    userPhoto: userPhoto,
                    historicalPhoto: historicalPhoto,
                    eraLabel: candidate.eraLabel,
                    revealFraction: $revealFraction,
                    historicalOffset: $historicalOffset,
                    historicalScale: $historicalScale
                )
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .plateFrame()

                alignmentControls
            }
            .instrumentCard()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                matchSummary(candidate)
                EyebrowText("Overlay withheld", color: Theme.albumen)
                Label(
                    "A precise-looking overlay would overstate this evidence.",
                    systemImage: "hand.raised.fill"
                )
                .font(.headline)
                .foregroundStyle(Theme.bone)
                if let reason = MatchExplanationPresenter(candidate: candidate).primaryRefusalReason {
                    Text("Primary reason: \(reason)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.albumen)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Review the candidate and provenance, choose another candidate, or return to orient again.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.boneMuted)
            }
            .instrumentCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Overlay withheld. "
                    + MatchExplanationPresenter(candidate: candidate).accessibilitySummary
            )
            .accessibilityIdentifier("overlay-refusal")
        }
    }

    private func matchSummary(_ candidate: MatchCandidate) -> some View {
        let presenter = MatchExplanationPresenter(candidate: candidate)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: dispositionSymbol(candidate.confidence.disposition))
                .font(.title2)
                .foregroundStyle(dispositionColor(candidate.confidence.disposition))
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.photo.title)
                    .font(.headline)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presenter.title)
                    .font(Theme.serifTitle)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presenter.candidateContext)
                    .font(Theme.metaFont)
                    .foregroundStyle(Theme.boneMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presenter.calibrationNote)
                    .font(Theme.metaFont)
                    .foregroundStyle(Theme.boneMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presenter.accessibilitySummary)
        .accessibilityIdentifier("match-confidence-summary")
    }

    private var alignmentControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowText("Adjust alignment", color: Theme.albumen)
                Spacer()
                Button("Reset") {
                    historicalOffset = .zero
                    historicalScale = 1
                }
                .frame(minHeight: 44)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.bone)
            }

            alignmentSlider(
                title: "Horizontal",
                value: Binding(
                    get: { historicalOffset.width },
                    set: {
                        historicalOffset = CGSize(
                            width: $0,
                            height: historicalOffset.height
                        )
                    }
                ),
                range: -80...80,
                valueText: "\(Int(historicalOffset.width)) points"
            )
            alignmentSlider(
                title: "Vertical",
                value: Binding(
                    get: { historicalOffset.height },
                    set: {
                        historicalOffset = CGSize(
                            width: historicalOffset.width,
                            height: $0
                        )
                    }
                ),
                range: -80...80,
                valueText: "\(Int(historicalOffset.height)) points"
            )
            alignmentSlider(
                title: "Scale",
                value: $historicalScale,
                range: 0.8...1.2,
                valueText: "\(Int(historicalScale * 100)) percent"
            )
        }
        .accessibilityIdentifier("alignment-controls")
    }

    private func alignmentSlider(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(valueText)
                        .foregroundStyle(Theme.boneMuted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(valueText)
                        .foregroundStyle(Theme.boneMuted)
                }
            }
            .font(Theme.metaFont)
            Slider(value: value, in: range)
                .tint(Theme.albumen)
                .accessibilityLabel("Historical image \(title.lowercased()) alignment")
                .accessibilityValue(valueText)
        }
        .foregroundStyle(Theme.bone)
    }

    private func provenanceCard(_ candidate: MatchCandidate) -> some View {
        let presenter = MatchExplanationPresenter(candidate: candidate)
        return VStack(alignment: .leading, spacing: 8) {
            EyebrowText("Archive details", color: Theme.albumen)
                .accessibilityAddTraits(.isHeader)
            provenanceRow("Archive", candidate.photo.attribution)
            provenanceRow("Source", presenter.archiveName)
            provenanceRow("Archive date", candidate.eraLabel ?? "Unavailable")
            provenanceRow(
                "Rights link",
                candidate.photo.rightsURI == nil
                    ? "Unavailable"
                    : "Present — not independently verified"
            )
            if let rights = candidate.photo.rightsURI,
               let url = URL(string: rights) {
                Link("Open archive rights statement", destination: url)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.bone)
            }
            Divider()
                .overlay(Theme.boneMuted.opacity(0.35))
            DisclosureGroup(isExpanded: $isLineageExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Afterimage does not synthesize archive links, coordinate origins, ingestion versions, or confidence values that the bundled index did not store.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.boneMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(presenter.provenanceRows) { row in
                        provenanceRow(row.label, row.value)
                    }
                }
                .padding(.top, 8)
                .accessibilityIdentifier("match-provenance-lineage-details")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lineage details")
                        .font(.headline)
                        .foregroundStyle(Theme.bone)
                        .accessibilityAddTraits(.isHeader)
                    Text(presenter.provenanceSummary)
                        .font(.caption)
                        .foregroundStyle(Theme.boneMuted)
                }
            }
            .tint(Theme.bone)
            .accessibilityHint("Expands technical provenance details and missing lineage fields")
        }
        .instrumentCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("match-provenance")
    }

    private func provenanceRow(_ label: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(Theme.boneMuted)
                Spacer(minLength: 12)
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.bone)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(Theme.boneMuted)
                Text(value)
                    .foregroundStyle(Theme.bone)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func saveSection(_ candidate: MatchCandidate) -> some View {
        if candidate.confidence.mayPresentOverlay,
           let historicalPhoto = candidate.thumbnail {
            VStack(alignment: .leading, spacing: 10) {
                EyebrowText("Save locally", color: Theme.albumen)
                Text("Save this before/after pair inside Afterimage. It is not added to Photos or uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.boneMuted)
                SlabButton(title: isSaving ? "Saving…" : "Save Before/After Pair") {
                    Task {
                        await savePair(candidate, historicalPhoto: historicalPhoto)
                    }
                }
                .disabled(isSaving || savedCandidateID == candidate.id)
                .accessibilityHint("Saves an image only in Afterimage's protected local storage")

                Text("Sharing opens the system share sheet. You choose whether and where a copy goes.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.boneMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(
                    item: PlateExport(
                        userPhoto: userPhoto,
                        historicalPhoto: historicalPhoto,
                        match: candidate,
                        revealFraction: revealFraction,
                        historicalOffset: historicalOffset,
                        historicalScale: historicalScale
                    ),
                    preview: SharePreview(
                        candidate.photo.title,
                        image: Image(uiImage: historicalPhoto)
                    )
                ) {
                    Label("Share a Copy", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Theme.bone)
                .accessibilityHint("Opens the system share sheet; nothing is shared until you choose a destination")
                if let saveMessage {
                    Text(saveMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.bone)
                        .accessibilityIdentifier("local-save-result")
                        .accessibilityFocused($saveResultFocused)
                }
            }
            .instrumentCard()
        }
    }

    @MainActor
    private func savePair(_ candidate: MatchCandidate, historicalPhoto: UIImage) async {
        isSaving = true
        defer {
            isSaving = false
            saveResultFocused = true
        }
        do {
            let data = try PlateExport(
                userPhoto: userPhoto,
                historicalPhoto: historicalPhoto,
                match: candidate,
                revealFraction: revealFraction,
                historicalOffset: historicalOffset,
                historicalScale: historicalScale
            ).renderPNG()
            _ = try await Task.detached(priority: .utility) {
                try LocalPairStore().save(pngData: data)
            }.value
            saveMessage = "Saved on this device."
            savedCandidateID = candidate.id
        } catch {
            saveMessage = "Could not save the pair. Your original photo was not changed."
        }
    }

    private func markCompositionChanged() {
        guard savedCandidateID != nil else { return }
        savedCandidateID = nil
        saveMessage = nil
        saveResultFocused = false
    }

    private func dispositionSymbol(_ disposition: MatchDisposition) -> String {
        switch disposition {
        case .confident: "checkmark.seal.fill"
        case .uncertain: "questionmark.diamond.fill"
        case .insufficientEvidence: "ellipsis.circle.fill"
        case .conflictingSignals: "exclamationmark.triangle.fill"
        case .unavailableLocation: "location.slash.fill"
        case .noMatch: "photo.badge.exclamationmark"
        }
    }

    private func dispositionColor(_ disposition: MatchDisposition) -> Color {
        switch disposition {
        case .confident: .green
        case .uncertain, .conflictingSignals: Theme.albumen
        case .insufficientEvidence, .unavailableLocation, .noMatch: Theme.boneMuted
        }
    }
}

private extension View {
    func instrumentCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.plateRaised, in: RoundedRectangle(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.boneFaint.opacity(0.35), lineWidth: 1)
            }
    }
}
