import SwiftUI

struct ForYouRailView: View {
    let events: [PeakEvent]
    var title: String = "For you"
    var subtitle: String? = nil
    var onSelect: (PeakEvent) -> Void
    var onDismiss: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                PeakAppLogo(size: 28, showGlow: false)

                VStack(alignment: .leading, spacing: 3) {
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
                        .frame(minHeight: 44)
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
                        .buttonStyle(.plain)
                        .peakPressable(haptic: false)
                        .peakAppear(delay: PeakMotion.staggerDelay(index: index, step: 0.05, cap: 4))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func heroCard(_ event: PeakEvent) -> some View {
        let isLight = colorScheme == .light
        return VStack(alignment: .leading, spacing: 10) {
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
                .frame(minHeight: 54, alignment: .topLeading)

            HStack(alignment: .firstTextBaseline) {
                if let p = event.displayProbability {
                    Text(PeakFormat.cents(p))
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.primary)
                        .peakNumeric(value: p)
                }
                Spacer()
                Text(PeakFormat.compactCurrency(event.volume24hr))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
