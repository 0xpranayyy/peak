import SwiftUI

struct ForYouRailView: View {
    let events: [PeakEvent]
    var title: String = "For you"
    var subtitle: String? = nil
    /// CLOB-enriched display odds keyed by event id (same map as Markets list).
    var displayedOdds: [String: Double] = [:]
    var onSelect: (PeakEvent) -> Void
    var onDismiss: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                PeakAppLogo(size: 28, showGlow: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if let onDismiss {
                    Button("Dismiss", action: onDismiss)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PeakBrand.mid)
                        .frame(minHeight: PeakLayout.minTap)
                }
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        Button {
                            PeakHaptics.selection()
                            onSelect(event)
                        } label: {
                            heroCard(event)
                        }
                        .buttonStyle(.peakPressable(haptic: false))
                        .peakAppear(delay: PeakMotion.staggerDelay(index: index, step: 0.05, cap: 4))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func probability(for event: PeakEvent) -> Double? {
        event.resolvedDisplayProbability(enriched: displayedOdds[event.id])
    }

    private func heroCard(_ event: PeakEvent) -> some View {
        let isLight = colorScheme == .light
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                if let category = MarketCategory.primaryLabel(for: event) {
                    Text(category.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(PeakBrand.mid)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PeakBrand.mid.opacity(0.7))
            }

            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 48, alignment: .topLeading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let p = probability(for: event) {
                    Text(PeakFormat.cents(p))
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.primary)
                        .peakNumeric(value: p)
                }
                Spacer(minLength: 4)
                Text(PeakFormat.compactCurrency(event.volume24hr))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: PeakLayout.cardRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: PeakLayout.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                PeakBrand.mid.opacity(isLight ? 0.14 : 0.18),
                                PeakBrand.deep.opacity(isLight ? 0.04 : 0.08),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: PeakLayout.cardRadius, style: .continuous)
                .strokeBorder(
                    PeakBrand.mid.opacity(isLight ? 0.18 : 0.22),
                    lineWidth: 1
                )
        )
        .shadow(
            color: PeakBrand.deep.opacity(isLight ? 0.06 : 0.18),
            radius: 10,
            y: 4
        )
    }
}
