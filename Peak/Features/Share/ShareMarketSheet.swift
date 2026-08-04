import SwiftUI
import UIKit

// MARK: - Shared postcard chrome (Peak-original — not a receipt clone)

/// Soft Peak paper postcard chrome — calm ink, teal accent.
/// Trade fill shares use a separate modern card in `PeakTradeShareCard`.
enum PeakPostcard {
    static let paper = Color(red: 0.975, green: 0.978, blue: 0.972)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.11)
    static let mute = Color(red: 0.42, green: 0.46, blue: 0.48)
    static let rule = Color(red: 0.82, green: 0.85, blue: 0.84)
    static let teal = Color(red: 0.12, green: 0.48, blue: 0.42)
    static let win = Color(red: 0.10, green: 0.52, blue: 0.38)
    static let loss = Color(red: 0.72, green: 0.28, blue: 0.32)
    static let stage = Color(red: 0.06, green: 0.18, blue: 0.17)

    /// Brighter teal for the odds bar and sparkline — `teal` is tuned for text
    /// on paper and reads muddy as a large filled shape.
    static let tealBright = Color(red: 0.16, green: 0.62, blue: 0.54)
    /// Luminous mint for buy fills / share-card hero energy — pair with `win`.
    static let winBright = Color(red: 0.22, green: 0.78, blue: 0.55)
    /// The trailing outcome. Warm slate rather than red: second place is not a
    /// loss, and a red bar reads as one.
    static let slate = Color(red: 0.58, green: 0.62, blue: 0.63)

    /// A card shared to a story sits in a 9:16 frame. The market card is
    /// taller than it was so the odds bar and sparkline get room.
    static let cardWidth: CGFloat = 390
    static let cardHeight: CGFloat = 560
    /// The position card carries four numbers and no chart. At the market
    /// card's height it renders with a third of the paper empty.
    static let positionCardHeight: CGFloat = 520
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
    /// `nil` renders the wordmark alone, sized to its content.
    ///
    /// The card footer previously carried a date, the wordmark *and* a "Open in
    /// Peak" call to action. Three items in one narrow row meant something
    /// always wrapped — first the CTA, then the wordmark to "pea / k", then the
    /// date. The CTA is the one to drop: it cannot be tapped in a static image,
    /// and the header already brands the card.
    var trailing: String? = "Trade on Peak"
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if let trailing {
                Spacer(minLength: 6)
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(light ? PeakPostcard.mute : .white.opacity(0.55))
    }
}

/// Label · value row used on postcard share cards.
struct PeakPostcardStatRow: View {
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

struct PeakPostcardRule: View {
    var body: some View {
        Rectangle()
            .fill(PeakPostcard.rule)
            .frame(height: 1)
            .padding(.vertical, 16)
    }
}

struct PeakPostcardStage: View {
    var body: some View {
        ZStack {
            PeakPostcard.stage

            // Soft horizon — Peak depth, not a photo backdrop.
            LinearGradient(
                colors: [
                    PeakPostcard.teal.opacity(0.30),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            // Warm counter-glow bottom-right, so the frame around the paper is
            // not a flat block of one colour on the two edges that show most.
            RadialGradient(
                colors: [PeakPostcard.tealBright.opacity(0.24), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 320
            )

            // Vignette to settle the corners.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.30)],
                center: .center,
                startRadius: 160,
                endRadius: 420
            )
        }
    }
}

/// The market's own artwork, pre-resolved to a `UIImage`.
///
/// Takes a `UIImage` rather than a URL on purpose: `ImageRenderer` snapshots
/// synchronously and will not wait on `AsyncImage`, so anything still loading
/// renders as a blank tile. The caller fetches first — see
/// `PeakShareCardRenderer.loadIcon`.
struct PeakShareMarketIcon: View {
    let image: UIImage?
    var size: CGFloat = 58
    var corner: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(PeakPostcard.teal.opacity(0.10))
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                } else {
                    // Fallback when the market has no artwork or it failed to
                    // load. The Peak mark is a deliberate stand-in, not an
                    // error state — the card must still look finished.
                    Image("PeakLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: size * 0.52, height: size * 0.52)
                        .clipShape(RoundedRectangle(cornerRadius: corner * 0.45, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(PeakPostcard.rule, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

/// Two-outcome odds as a proportional bar.
///
/// Replaces a pair of label/value rows. The same two numbers, but the split is
/// legible at a glance in a feed, which is the only place this card is ever
/// seen — nobody reads a shared image carefully.
private struct PeakPostcardOddsBar: View {
    let yes: Double
    let no: Double
    let yesLabel: String
    let noLabel: String

    private var total: Double { max(0.0001, yes + no) }
    private var yesShare: Double { min(max(yes / total, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(yesLabel.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(PeakPostcard.mute)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(PeakFormat.percent(yes, digits: 0))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(PeakPostcard.teal)
            }

            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = max(0, geo.size.width - gap)
                HStack(spacing: gap) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [PeakPostcard.teal, PeakPostcard.tealBright],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: usable * yesShare)
                    Capsule()
                        .fill(PeakPostcard.slate.opacity(0.35))
                }
            }
            .frame(height: 12)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(noLabel.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(PeakPostcard.mute)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(PeakFormat.percent(no, digits: 0))
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(PeakPostcard.ink.opacity(0.65))
            }
        }
    }
}

struct PeakPostcardPaper: View {
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

enum PeakShareDate {
    /// Deliberately compact. Odds move, so the time matters, but a full
    /// "27 Jul 2026 at 11:09 AM" crowds the footer into wrapping.
    static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM · HH:mm")
        return formatter.string(from: date)
    }

    /// Ultra-short day stamp for compact chrome.
    static func compactDay(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - Market postcard

/// Story-ready market card — postcard layout with odds + stamp date.
struct PeakShareCard: View {
    let event: PeakEvent
    let market: Market?
    var history: [PricePoint] = []
    /// Pre-resolved market artwork. See `PeakShareMarketIcon`.
    var icon: UIImage? = nil

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
                        // Icon leads the row: it is the one element that makes a
                        // shared card recognisable while scrolling past it.
                        HStack(alignment: .top, spacing: 14) {
                            PeakShareMarketIcon(image: icon)

                            VStack(alignment: .leading, spacing: 6) {
                                if let category {
                                    Text(category.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .tracking(1.2)
                                        .foregroundStyle(PeakPostcard.teal)
                                }
                                Text(event.title)
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(PeakPostcard.ink)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }

                        if market != nil, question != event.title {
                            Text(question)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(PeakPostcard.mute)
                                .lineLimit(2)
                                .padding(.top, 10)
                        }

                        PeakPostcardRule()

                        PeakPostcardOddsBar(
                            yes: yes,
                            no: no,
                            yesLabel: market?.yesLabel ?? "Yes",
                            noLabel: market?.noLabel ?? "No"
                        )

                        if history.count >= 2 {
                            marketSparkline
                                .frame(minHeight: 56, maxHeight: .infinity)
                                .padding(.top, 18)
                        }

                        // Small when a chart is present (it takes the slack),
                        // large when there is none (it pushes the footer down).
                        Spacer(minLength: 12)

                        PeakPostcardRule()

                        PeakPostcardStatRow(
                            label: "24h volume",
                            value: PeakFormat.compactCurrency(event.volume24hr),
                            valueSize: 18
                        )

                        HStack(alignment: .center, spacing: 12) {
                            Text(PeakShareDate.stamp())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PeakPostcard.mute)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            PeakShareBrandFooter(trailing: nil, light: true)
                        }
                        .padding(.top, 18)
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
            // Inset vertically so the extremes are not clipped by the stroke.
            let top: CGFloat = 3
            let usable = max(1, h - top * 2)

            let points: [CGPoint] = history.enumerated().map { index, entry in
                CGPoint(
                    x: w * CGFloat(index) / CGFloat(max(history.count - 1, 1)),
                    y: top + usable - (CGFloat((entry.price - minP) / span) * usable)
                )
            }

            ZStack {
                // Filled area under the line — gives the chart weight at the
                // small size a share card allows.
                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: h))
                    path.addLine(to: first)
                    for p in points.dropFirst() { path.addLine(to: p) }
                    path.addLine(to: CGPoint(x: last.x, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [PeakPostcard.tealBright.opacity(0.28), PeakPostcard.tealBright.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for p in points.dropFirst() { path.addLine(to: p) }
                }
                .stroke(
                    LinearGradient(
                        colors: [PeakPostcard.teal, PeakPostcard.tealBright],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                // Marks where the line ends, so the eye lands on "now".
                if let last = points.last {
                    Circle()
                        .fill(PeakPostcard.paper)
                        .frame(width: 9, height: 9)
                        .overlay { Circle().strokeBorder(PeakPostcard.tealBright, lineWidth: 2.5) }
                        .position(last)
                }
            }
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

                        HStack(alignment: .center, spacing: 12) {
                            Text(PeakShareDate.stamp())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PeakPostcard.mute)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            PeakShareBrandFooter(trailing: nil, light: true)
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(22)
        }
        .frame(width: PeakPostcard.cardWidth, height: PeakPostcard.positionCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Renderer + sheets

enum PeakShareCardRenderer {
    @MainActor
    static func image(
        event: PeakEvent,
        market: Market?,
        history: [PricePoint] = [],
        icon: UIImage? = nil
    ) -> UIImage? {
        let card = PeakShareCard(event: event, market: market, history: history, icon: icon)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Fetch the market artwork before rendering.
    ///
    /// `ImageRenderer` snapshots synchronously and will not wait on an in-flight
    /// `AsyncImage`, which is why this card previously showed the Peak logo in
    /// place of the market's own image. Resolving to a `UIImage` first is the
    /// whole fix.
    ///
    /// Returns `nil` on any failure — a missing icon degrades to the Peak mark
    /// rather than blocking or failing the share.
    static func loadIcon(for event: PeakEvent, market: Market?) async -> UIImage? {
        guard let url = market?.imageURL ?? event.imageURL else { return nil }
        var request = URLRequest(url: url)
        // Browsing the list already populated the shared cache in the common
        // case, so this is usually free.
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        guard let image = UIImage(data: data) else { return nil }
        return image
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
                let icon = await PeakShareCardRenderer.loadIcon(for: event, market: market)
                image = PeakShareCardRenderer.image(
                    event: event,
                    market: market,
                    history: history,
                    icon: icon
                )
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
