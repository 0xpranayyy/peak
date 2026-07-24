import SwiftUI

struct ProbabilityBadge: View {
    let probability: Double

    var body: some View {
        Text(PeakFormat.cents(probability))
            .font(.headline.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel("Probability \(PeakFormat.percent(probability))")
    }
}

struct EventRowView: View {
    let event: PeakEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
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

            if let p = event.displayProbability {
                ProbabilityBadge(probability: p)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct MarketOutcomeBar: View {
    let market: Market

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(market.question)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)

            GeometryReader { geo in
                let yes = max(0.02, min(0.98, market.yesPrice))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: geo.size.width * yes)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(market.yesLabel) \(PeakFormat.cents(market.yesPrice))")
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(market.noLabel) \(PeakFormat.cents(market.noPrice))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

struct LoadingErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
