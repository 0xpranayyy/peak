import SwiftUI
import UIKit

// MARK: - Shared brand chrome for share images

/// Logo + wordmark for rendered share cards (Messages, Instagram, X).
struct PeakShareBrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("PeakLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Peak")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                Text("Prediction markets")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peak")
    }
}

struct PeakShareBrandFooter: View {
    var trailing: String = "Trade on Peak"

    var body: some View {
        HStack(spacing: 8) {
            Image("PeakLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text("peak")
                .font(.caption.weight(.bold))
                .tracking(0.6)

            Spacer(minLength: 0)

            Text(trailing)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white.opacity(0.55))
    }
}

private enum PeakSharePalette {
    static let bgTop = Color(red: 0.04, green: 0.11, blue: 0.12)
    static let bgMid = Color(red: 0.07, green: 0.20, blue: 0.22)
    static let bgBottom = Color(red: 0.04, green: 0.09, blue: 0.10)
    static let bloom = Color(red: 0.28, green: 0.78, blue: 0.62)
    static let accentText = Color(red: 0.72, green: 0.96, blue: 0.88)
}

/// Story-ready market card for Messages / Instagram / X.
struct PeakShareCard: View {
    let event: PeakEvent
    let market: Market?
    var history: [PricePoint] = []

    private var yes: Double { market?.yesPrice ?? event.displayProbability ?? 0.5 }
    private var no: Double { market?.noPrice ?? max(0, 1 - yes) }
    private var category: String? { MarketCategory.primaryLabel(for: event) }

    var body: some View {
        ZStack {
            atmosphere

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    PeakShareBrandHeader()
                    Spacer(minLength: 8)
                    if let category {
                        Text(category.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.bottom, 28)

                Text(event.title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 28)

                HStack(spacing: 12) {
                    oddsPill(
                        label: market?.yesLabel ?? "Yes",
                        cents: PeakFormat.cents(yes),
                        emphasis: true
                    )
                    oddsPill(
                        label: market?.noLabel ?? "No",
                        cents: PeakFormat.cents(no),
                        emphasis: false
                    )
                }
                .padding(.bottom, 22)

                if history.count >= 2 {
                    sparkline
                        .frame(height: 56)
                        .padding(.bottom, 22)
                }

                Spacer(minLength: 12)

                HStack(alignment: .bottom) {
                    Label(PeakFormat.compactCurrency(event.volume24hr) + " 24h", systemImage: "chart.bar.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    PeakShareBrandFooter(trailing: "Trade on Peak")
                }
            }
            .padding(28)
        }
        .frame(width: 390, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var atmosphere: some View {
        ZStack {
            LinearGradient(
                colors: [PeakSharePalette.bgTop, PeakSharePalette.bgMid, PeakSharePalette.bgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [PeakSharePalette.bloom.opacity(0.40), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .frame(width: 360, height: 280)
                .offset(x: 110, y: -160)
                .blur(radius: 6)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [PeakBrand.deep.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 200
                    )
                )
                .frame(width: 340, height: 300)
                .offset(x: -130, y: 200)
                .blur(radius: 10)
        }
    }

    private func oddsPill(label: String, cents: String, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.65))
            Text(cents)
                .font(.system(size: 34, weight: .bold).monospacedDigit())
                .foregroundStyle(emphasis ? PeakSharePalette.accentText : .white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color.white.opacity(emphasis ? 0.14 : 0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(emphasis ? 0.28 : 0.1), lineWidth: 1)
        )
    }

    private var sparkline: some View {
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
                PeakSharePalette.bloom,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

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

                    Text("Share this market with current odds.")
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
