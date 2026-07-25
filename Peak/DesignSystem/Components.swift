import SwiftUI

struct ProbabilityBadge: View {
    let probability: Double
    @ScaledMetric(relativeTo: .headline) private var horizontalPadding: CGFloat = 10
    @ScaledMetric(relativeTo: .headline) private var verticalPadding: CGFloat = 6

    var body: some View {
        Text(PeakFormat.cents(probability))
            .font(.headline.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
            .peakNumeric(value: probability)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .peakFloatingChrome()
            .accessibilityLabel("Odds \(PeakFormat.cents(probability)), \(PeakFormat.percent(probability))")
    }
}

struct PeakCategoryChip: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            PeakHaptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 36)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
            .animation(PeakMotion.snappy, value: selected)
        }
        .peakPressable(haptic: false)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct EventRowView: View {
    let event: PeakEvent
    /// CLOB mid / last-trade display odds when enriched; else Gamma snapshot.
    var displayedProbability: Double? = nil

    private var categoryLabel: String? {
        MarketCategory.primaryLabel(for: event)
    }

    private var probability: Double? {
        displayedProbability ?? event.displayProbability
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let categoryLabel {
                    Text(categoryLabel.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }

                Text(event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Label(PeakFormat.compactCurrency(event.volume24hr), systemImage: "chart.bar.fill")
                    if let end = event.endDate {
                        Label(PeakFormat.relativeEnd(end), systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 8)

            if let p = probability {
                ProbabilityBadge(probability: p)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct MarketOutcomeBar: View {
    let market: Market
    /// When set (event detail), prefer CLOB display odds over Gamma snapshot.
    var displayedYes: Double? = nil

    private var yes: Double {
        displayedYes ?? market.yesPrice
    }

    private var no: Double {
        max(0, 1 - yes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(market.question)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)

            GeometryReader { geo in
                let width = max(0.02, min(0.98, yes))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: geo.size.width * width)
                        .animation(PeakMotion.soft, value: yes)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(market.yesLabel) \(PeakFormat.cents(yes))")
                    .foregroundStyle(.primary)
                    .peakNumeric(value: yes)
                Spacer()
                Text("\(market.noLabel) \(PeakFormat.cents(no))")
                    .foregroundStyle(.secondary)
                    .peakNumeric(value: no)
            }
            .font(.caption.monospacedDigit().weight(.medium))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(market.question). \(market.yesLabel) \(PeakFormat.percent(yes)), \(market.noLabel) \(PeakFormat.percent(no))"
        )
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var kind: PeakEmptyKind = .markets
    /// Kept for call-site compatibility; visual uses `kind` composition.
    var systemImage: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    init(
        systemImage: String,
        title: String,
        message: String,
        kind: PeakEmptyKind? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.kind = kind ?? Self.inferredKind(from: systemImage)
        self.actionTitle = actionTitle
        self.action = action
    }

    init(
        kind: PeakEmptyKind,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.systemImage = kind.primarySymbol
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 16) {
                PeakEmptyVisual(kind: kind)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .controlSize(.large)
                    .frame(minHeight: 44)
            }
        }
    }

    private static func inferredKind(from systemImage: String) -> PeakEmptyKind {
        let s = systemImage.lowercased()
        if s.contains("star") || s.contains("bookmark") { return .watchlist }
        if s.contains("wallet") || s.contains("briefcase") { return .portfolio }
        if s.contains("magnifying") || s.contains("sparkle") { return .search }
        if s.contains("chart") { return .chart }
        return .markets
    }
}

struct LoadingErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(PeakUserCopy.sanitize(message, fallback: "Couldn’t load. Try again."))
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .controlSize(.large)
        }
    }
}
