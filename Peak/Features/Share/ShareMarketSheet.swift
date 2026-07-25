import SwiftUI
import UIKit

// MARK: - Shared postcard chrome (Peak-original — not a receipt clone)

/// Soft Peak paper postcard — calm ink, teal accent, no perforated ticket motif.
enum PeakPostcard {
    static let paper = Color(red: 0.975, green: 0.978, blue: 0.972)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.11)
    static let mute = Color(red: 0.42, green: 0.46, blue: 0.48)
    static let rule = Color(red: 0.82, green: 0.85, blue: 0.84)
    static let teal = Color(red: 0.12, green: 0.48, blue: 0.42)
    static let win = Color(red: 0.10, green: 0.52, blue: 0.38)
    static let loss = Color(red: 0.72, green: 0.28, blue: 0.32)
    static let stage = Color(red: 0.06, green: 0.18, blue: 0.17)

    static let cardWidth: CGFloat = 390
    static let cardHeight: CGFloat = 520
}

struct PeakShareBrandHeader: View {
    var light: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image("PeakLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            light ? PeakPostcard.rule : Color.white.opacity(0.22),
                            lineWidth: 1
                        )
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Peak")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.3)
                Text("Markets")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(light ? PeakPostcard.mute : .white.opacity(0.5))
            }
        }
        .foregroundStyle(light ? PeakPostcard.ink : .white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peak")
    }
}

struct PeakShareBrandFooter: View {
    var trailing: String = "Trade on Peak"
    var light: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image("PeakLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text("peak")
                .font(.caption.weight(.bold))
                .tracking(0.8)

            Spacer(minLength: 0)

            Text(trailing)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(light ? PeakPostcard.mute : .white.opacity(0.55))
    }
}

/// Label · value row used on postcard share cards.
private struct PeakPostcardStatRow: View {
    let label: String
    let value: String
    var valueColor: Color = PeakPostcard.ink
    var valueSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(PeakPostcard.mute)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct PeakPostcardRule: View {
    var body: some View {
        Rectangle()
            .fill(PeakPostcard.rule)
            .frame(height: 1)
            .padding(.vertical, 16)
    }
}

private struct PeakPostcardStage: View {
    var body: some View {
        ZStack {
            PeakPostcard.stage
            // Soft horizon — Peak depth, not a photo backdrop.
            LinearGradient(
                colors: [
                    PeakPostcard.teal.opacity(0.28),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
    }
}

private struct PeakPostcardPaper: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(PeakPostcard.paper)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
    }
}

private enum PeakShareDate {
    static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Market postcard

/// Story-ready market card — postcard layout with odds + stamp date.
struct PeakShareCard: View {
    let event: PeakEvent
    let market: Market?
    var history: [PricePoint] = []

    private var yes: Double { market?.yesPrice ?? event.displayProbability ?? 0.5 }
    private var no: Double { market?.noPrice ?? max(0, 1 - yes) }
    private var category: String? { MarketCategory.primaryLabel(for: event) }
    private var question: String { market?.question ?? event.title }

    var body: some View {
        ZStack {
            PeakPostcardStage()

            VStack(spacing: 0) {
                PeakShareBrandHeader()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 18)

                ZStack {
                    PeakPostcardPaper()

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let category {
                                    Text(category.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .tracking(1.2)
                                        .foregroundStyle(PeakPostcard.teal)
                                }
                                Text(event.title)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(PeakPostcard.ink)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            // Static stamp — ImageRenderer won't wait on AsyncImage.
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(PeakPostcard.teal.opacity(0.12))
                                Image("PeakLogo")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .frame(width: 56, height: 56)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(PeakPostcard.rule, lineWidth: 1)
                            }
                        }

                        if market != nil, question != event.title {
                            Text(question)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(PeakPostcard.mute)
                                .lineLimit(2)
                                .padding(.top, 10)
                        }

                        PeakPostcardRule()

                        PeakPostcardStatRow(
                            label: (market?.yesLabel ?? "Yes"),
                            value: PeakFormat.percent(yes, digits: 0),
                            valueColor: PeakPostcard.teal,
                            valueSize: 28
                        )
                        .padding(.bottom, 12)

                        PeakPostcardStatRow(
                            label: (market?.noLabel ?? "No"),
                            value: PeakFormat.percent(no, digits: 0),
                            valueSize: 22
                        )

                        PeakPostcardRule()

                        PeakPostcardStatRow(
                            label: "24h volume",
                            value: PeakFormat.compactCurrency(event.volume24hr),
                            valueSize: 18
                        )

                        if history.count >= 2 {
                            PeakPostcardRule()
                            marketSparkline
                                .frame(height: 44)
                        }

                        Spacer(minLength: 16)

                        HStack(alignment: .bottom) {
                            Text(PeakShareDate.stamp())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PeakPostcard.mute)
                            Spacer()
                            PeakShareBrandFooter(trailing: "Open in Peak", light: true)
                                .frame(maxWidth: 160)
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(22)
        }
        .frame(width: PeakPostcard.cardWidth, height: PeakPostcard.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var marketSparkline: some View {
        let prices = history.map(\.price)
        let minP = prices.min() ?? 0
        let maxP = prices.max() ?? 1
        let span = max(0.01, maxP - minP)

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                for (index, point) in history.enumerated() {
                    let x = w * CGFloat(index) / CGFloat(max(history.count - 1, 1))
                    let y = h - (CGFloat((point.price - minP) / span) * h)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                PeakPostcard.teal,
                style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Position postcard

struct PeakPositionShareCard: View {
    let position: PortfolioPosition

    /// Cost basis (shares × average entry).
    private var boughtUSD: Double { position.size * position.avgPrice }
    /// Binary markets pay $1 per share if the outcome wins.
    private var toWinUSD: Double { position.size }
    private var chance: Double { position.avgPrice }
    private var isUp: Bool { position.percentPnl >= 0 }

    var body: some View {
        ZStack {
            PeakPostcardStage()

            VStack(spacing: 0) {
                PeakShareBrandHeader()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 18)

                ZStack {
                    PeakPostcardPaper()

                    VStack(alignment: .leading, spacing: 0) {
                        Text(position.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PeakPostcard.mute)
                            .lineLimit(2)

                        Text(position.outcome)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(PeakPostcard.ink)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)

                        PeakPostcardRule()

                        PeakPostcardStatRow(
                            label: "Bought",
                            value: PeakFormat.usd(boughtUSD),
                            valueSize: 22
                        )
                        .padding(.bottom, 14)

                        PeakPostcardStatRow(
                            label: "Chance",
                            value: PeakFormat.percent(chance, digits: 0),
                            valueSize: 22
                        )

                        PeakPostcardRule()

                        PeakPostcardStatRow(
                            label: "To win",
                            value: PeakFormat.usd(toWinUSD),
                            valueColor: PeakPostcard.win,
                            valueSize: 34
                        )

                        HStack {
                            Text(isUp ? "Up \(String(format: "%.1f%%", position.percentPnl))" : "Down \(String(format: "%.1f%%", abs(position.percentPnl)))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(isUp ? PeakPostcard.win : PeakPostcard.loss)
                            Spacer()
                            Text("Now \(PeakFormat.cents(position.currentPrice))")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(PeakPostcard.mute)
                        }
                        .padding(.top, 12)

                        Spacer(minLength: 16)

                        HStack(alignment: .bottom) {
                            Text(PeakShareDate.stamp())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PeakPostcard.mute)
                            Spacer()
                            PeakShareBrandFooter(trailing: "Trade on Peak", light: true)
                                .frame(maxWidth: 160)
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(22)
        }
        .frame(width: PeakPostcard.cardWidth, height: PeakPostcard.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Renderer + sheets

enum PeakShareCardRenderer {
    @MainActor
    static func image(
        event: PeakEvent,
        market: Market?,
        history: [PricePoint] = []
    ) -> UIImage? {
        let card = PeakShareCard(event: event, market: market, history: history)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    static func polymarketURL(for event: PeakEvent) -> URL? {
        guard let slug = event.slug, !slug.isEmpty else { return nil }
        return URL(string: "https://polymarket.com/event/\(slug)")
    }
}

struct ShareMarketSheet: View {
    let event: PeakEvent
    let market: Market?
    var history: [PricePoint] = []

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                            .padding(.horizontal, 20)
                            .accessibilityLabel("Share card for \(event.title)")
                            .accessibilityAddTraits(.isImage)
                    } else {
                        ProgressView("Rendering card…")
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }

                    Text("Share this market postcard with current odds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if let image {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(event.title, image: Image(uiImage: image))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }

                    if let url = PeakShareCardRenderer.polymarketURL(for: event) {
                        ShareLink(item: url) {
                            Label("Link", systemImage: "link")
                        }
                    }

                    Button {
                        guard let image else { return }
                        UIPasteboard.general.image = image
                        didCopy = true
                        PeakHaptics.press()
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(image == nil)
                }
            }
            .task {
                image = PeakShareCardRenderer.image(event: event, market: market, history: history)
            }
        }
        .presentationDetents([.medium, .large])
        .peakSheetChrome()
    }
}

struct SharePositionSheet: View {
    let position: PortfolioPosition
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                            .padding(.horizontal, 20)
                            .accessibilityLabel("Share card for \(position.title)")
                            .accessibilityAddTraits(.isImage)
                    } else {
                        ProgressView("Rendering card…")
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }

                    Text("Share your position as a Peak postcard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.vertical, 16)
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Share position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let image {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(position.title, image: Image(uiImage: image))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share position card")
                    }
                }
            }
            .task {
                let card = PeakPositionShareCard(position: position)
                let renderer = ImageRenderer(content: card)
                renderer.scale = 3
                renderer.isOpaque = true
                image = renderer.uiImage
            }
        }
        .presentationDetents([.medium, .large])
        .peakSheetChrome()
    }
}
