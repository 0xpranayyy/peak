import SwiftUI

struct ProbabilityBadge: View {
    let probability: Double
    var compact: Bool = false
    @ScaledMetric(relativeTo: .headline) private var horizontalPadding: CGFloat = 10
    @ScaledMetric(relativeTo: .headline) private var verticalPadding: CGFloat = 5

    var body: some View {
        Text(PeakFormat.cents(probability))
            .font((compact ? Font.subheadline : Font.headline).monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
            .peakNumeric(value: probability)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(PeakCanvas.inset, in: RoundedRectangle(cornerRadius: PeakLayout.badgeRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PeakLayout.badgeRadius, style: .continuous)
                    .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
            }
            .accessibilityLabel("Odds \(PeakFormat.cents(probability)), \(PeakFormat.percent(probability))")
    }
}

/// Trailing odds for market lists — type, not a fake button.
struct PeakOddsMetric: View {
    let probability: Double

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(PeakFormat.cents(probability))
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .peakNumeric(value: probability)
            Text(PeakFormat.percent(probability, digits: 0))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Odds \(PeakFormat.cents(probability)), \(PeakFormat.percent(probability))")
    }
}

struct PeakCategoryChip: View {
    @Environment(\.peakBrand) private var brand
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void

    private var shape: Capsule { Capsule(style: .continuous) }

    var body: some View {
        Button {
            PeakHaptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background {
                if selected {
                    shape.fill(brand.deep)
                }
            }
            .overlay {
                shape.strokeBorder(
                    selected ? Color.clear : PeakCanvas.hairline,
                    lineWidth: 1
                )
            }
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .contentShape(shape)
            .animation(PeakMotion.snappy, value: selected)
        }
        .peakPressable(haptic: false)
        .frame(minHeight: PeakLayout.minTap)
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
        event.resolvedDisplayProbability(enriched: displayedProbability)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PeakEventThumb(url: event.imageURL, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 0) {
                    if let categoryLabel {
                        Text(categoryLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        metaDot
                    }
                    Text(PeakFormat.compactCurrency(event.volume24hr))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                    if let end = event.endDate {
                        metaDot
                        Text(PeakFormat.relativeEnd(end))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let p = probability {
                PeakOddsMetric(probability: p)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var metaDot: some View {
        Text(" · ")
            .font(.caption.weight(.medium))
            .foregroundStyle(.quaternary)
    }
}

/// Small market / event image for list rows — falls back to a calm icon tile.
struct PeakEventThumb: View {
    @Environment(\.peakBrand) private var brand
    let url: URL?
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        PeakCanvas.inset
                            .overlay { ProgressView().controlSize(.mini) }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            PeakCanvas.inset
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(brand.mid.opacity(0.85))
        }
    }
}

/// Circular user avatar — remote Polymarket image, else initials tile.
struct PeakAvatar: View {
    @Environment(\.peakBrand) private var brand
    let imageURL: URL?
    var title: String = ""
    var size: CGFloat = 40
    var verified: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            initialsTile
                        case .empty:
                            PeakCanvas.inset
                                .overlay { ProgressView().controlSize(.mini) }
                        @unknown default:
                            initialsTile
                        }
                    }
                } else {
                    initialsTile
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(PeakCanvas.hairline, lineWidth: 1)
            }

            if verified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: max(10, size * 0.28)))
                    .foregroundStyle(PeakTradeStyle.buy)
                    .background(Circle().fill(PeakCanvas.elevated).padding(-1))
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }

    private var initialsTile: some View {
        ZStack {
            brand.mid.opacity(0.18)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(brand.mid)
        }
    }

    private var initials: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        if trimmed.lowercased().hasPrefix("0x"), trimmed.count >= 4 {
            return String(trimmed.suffix(2)).uppercased()
        }
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
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
                        .fill(PeakCanvas.inset)
                    Capsule()
                        .fill(PeakTradeStyle.buy.opacity(0.88))
                        .frame(width: geo.size.width * width)
                        .animation(PeakMotion.soft, value: yes)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(market.yesLabel) \(PeakFormat.cents(yes))")
                    .foregroundStyle(PeakTradeStyle.buy)
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
