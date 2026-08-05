import SwiftUI
import UIKit

// MARK: - Shared postcard chrome

/// Peak share postcard — dark shell + bright paper. High contrast, calm type,
/// accent only where it earns it (to-win green, loss red, Peak teal sparingly).
enum PeakPostcard {
    /// Bright paper — crisp against the dark shell.
    static let paper = Color(red: 0.995, green: 0.996, blue: 0.993)
    static let ink = Color(red: 0.06, green: 0.07, blue: 0.08)
    static let mute = Color(red: 0.46, green: 0.49, blue: 0.51)
    static let rule = Color(red: 0.88, green: 0.90, blue: 0.89)
    static let teal = Color(red: 0.14, green: 0.50, blue: 0.44)
    static let win = Color(red: 0.08, green: 0.58, blue: 0.40)
    static let loss = Color(red: 0.78, green: 0.26, blue: 0.30)
    /// Deep Peak shell — richer than flat muddy green.
    static let stage = Color(red: 0.045, green: 0.12, blue: 0.115)
    static let stageDeep = Color(red: 0.02, green: 0.055, blue: 0.052)

    /// Brighter teal for odds bar / sparkline fills.
    static let tealBright = Color(red: 0.18, green: 0.64, blue: 0.56)
    /// Luminous mint for buy / profit heroes.
    static let winBright = Color(red: 0.22, green: 0.82, blue: 0.52)
    /// Warm coral for sell / proceeds heroes (not a red "error").
    static let sell = Color(red: 0.88, green: 0.38, blue: 0.32)
    static let sellBright = Color(red: 1.00, green: 0.52, blue: 0.36)
    /// Soft sky for trade-receipt CTAs (not teal).
    static let sky = Color(red: 0.48, green: 0.74, blue: 1.00)
    /// Soft rose for NO outcome pills on dark receipts.
    static let noRose = Color(red: 1.00, green: 0.48, blue: 0.55)
    /// Subtle gold for avatar rings on dark receipts.
    static let gold = Color(red: 0.92, green: 0.74, blue: 0.42)
    /// Near-black charcoal stage for the trade receipt (not forest teal).
    static let charcoal = Color(red: 0.055, green: 0.058, blue: 0.068)
    /// Trailing outcome on odds bar — warm slate, not loss-red.
    static let slate = Color(red: 0.58, green: 0.62, blue: 0.63)

    static let cardWidth: CGFloat = 390
    static let cardHeight: CGFloat = 560
    /// Position card — huge outcome + four numbers, no chart.
    static let positionCardHeight: CGFloat = 540
    /// Trade receipt — header, market row, hero profit, 3-col stats, payout, footer.
    static let tradeCardHeight: CGFloat = 580

    static let shellCorner: CGFloat = 28
    static let paperCorner: CGFloat = 20
    static let shellPadding: CGFloat = 20
    static let paperPadding: CGFloat = 26
}

// MARK: - Brand

struct PeakShareBrandHeader: View {
    var light: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            Image("PeakLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            light ? PeakPostcard.rule : Color.white.opacity(0.28),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(light ? 0.06 : 0.35), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Peak")
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.35)
                Text("Markets")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(light ? PeakPostcard.mute : Color.white.opacity(0.42))
            }
        }
        .foregroundStyle(light ? PeakPostcard.ink : .white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peak")
    }
}

/// Compact ink pill — Peak mark + wordmark for paper footers.
struct PeakShareMarkPill: View {
    var body: some View {
        HStack(spacing: 5) {
            Image("PeakLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))

            Text("peak")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(Color.white.opacity(0.96))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(PeakPostcard.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peak")
    }
}

struct PeakShareBrandFooter: View {
    /// `nil` renders the wordmark alone. Prefer `PeakShareMarkPill` on paper.
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
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.35)
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
    var spacing: CGFloat = 18

    var body: some View {
        Rectangle()
            .fill(PeakPostcard.rule)
            .frame(height: 1)
            .padding(.vertical, spacing)
    }
}

struct PeakPostcardStage: View {
    var body: some View {
        ZStack {
            // Vertical depth — deep Peak green, not a flat mud block.
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.18, blue: 0.165),
                    PeakPostcard.stage,
                    PeakPostcard.stageDeep,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Soft teal bloom — upper-left brand light.
            RadialGradient(
                colors: [
                    PeakPostcard.tealBright.opacity(0.28),
                    Color.clear,
                ],
                center: UnitPoint(x: 0.12, y: 0.08),
                startRadius: 4,
                endRadius: 280
            )

            // Cool counter-glow bottom-right for edge separation.
            RadialGradient(
                colors: [
                    Color(red: 0.10, green: 0.32, blue: 0.30).opacity(0.45),
                    Color.clear,
                ],
                center: UnitPoint(x: 0.92, y: 0.88),
                startRadius: 8,
                endRadius: 300
            )

            // Soft vignette so paper floats.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.38)],
                center: .center,
                startRadius: 140,
                endRadius: 440
            )

            // Hairline sheen across the top edge of the shell.
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.18)
            )
        }
    }
}

/// Bright paper insert with soft lift shadow.
struct PeakPostcardPaper: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PeakPostcard.paperCorner, style: .continuous)
            .fill(PeakPostcard.paper)
            .overlay {
                RoundedRectangle(cornerRadius: PeakPostcard.paperCorner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
    }
}

/// Shared dark-shell + white-paper chrome for all Peak share cards.
struct PeakPostcardShell<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            PeakPostcardStage()

            VStack(spacing: 0) {
                PeakShareBrandHeader()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)

                ZStack {
                    PeakPostcardPaper()

                    content()
                        .padding(PeakPostcard.paperPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(PeakPostcard.shellPadding)
        }
        .frame(width: PeakPostcard.cardWidth, height: height)
        .clipShape(RoundedRectangle(cornerRadius: PeakPostcard.shellCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PeakPostcard.shellCorner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
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
            .fill(PeakPostcard.teal.opacity(0.08))
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                } else {
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
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(PeakPostcard.mute)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(PeakFormat.percent(yes, digits: 0))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
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
                        .fill(PeakPostcard.slate.opacity(0.28))
                }
            }
            .frame(height: 11)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(noLabel.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(PeakPostcard.mute)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(PeakFormat.percent(no, digits: 0))
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(PeakPostcard.ink.opacity(0.62))
            }
        }
    }
}

enum PeakShareDate {
    /// Compact stamp for market cards.
    static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM · HH:mm")
        return formatter.string(from: date)
    }

    /// Position / trade postcard footer — "Aug 5 at 11:55".
    static func postcardStamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d 'at' H:mm"
        return formatter.string(from: date)
    }

    /// Trade receipt footer — matches older prototype ("Aug 4 · 8:42 PM").
    static func receiptStamp(_ date: Date = Date()) -> String {
        postcardStamp(date)
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
        PeakPostcardShell(height: PeakPostcard.cardHeight) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    PeakShareMarketIcon(image: icon)

                    VStack(alignment: .leading, spacing: 6) {
                        if let category {
                            Text(category.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.3)
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

                Spacer(minLength: 12)

                PeakPostcardRule(spacing: 16)

                PeakPostcardStatRow(
                    label: "24h volume",
                    value: PeakFormat.compactCurrency(event.volume24hr),
                    valueSize: 18
                )

                HStack(alignment: .center, spacing: 12) {
                    Text(PeakShareDate.postcardStamp())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PeakPostcard.mute)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    PeakShareMarkPill()
                }
                .padding(.top, 18)
            }
        }
    }

    private var marketSparkline: some View {
        let prices = history.map(\.price)
        let minP = prices.min() ?? 0
        let maxP = prices.max() ?? 1
        let span = max(0.01, maxP - minP)

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let top: CGFloat = 3
            let usable = max(1, h - top * 2)

            let points: [CGPoint] = history.enumerated().map { index, entry in
                CGPoint(
                    x: w * CGFloat(index) / CGFloat(max(history.count - 1, 1)),
                    y: top + usable - (CGFloat((entry.price - minP) / span) * usable)
                )
            }

            ZStack {
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
                        colors: [PeakPostcard.tealBright.opacity(0.26), PeakPostcard.tealBright.opacity(0.02)],
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
        PeakPostcardShell(height: PeakPostcard.positionCardHeight) {
            VStack(alignment: .leading, spacing: 0) {
                Text(position.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PeakPostcard.mute)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(position.outcome)
                    .font(.system(size: 58, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(PeakPostcard.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .padding(.top, 10)

                PeakPostcardRule()

                PeakPostcardStatRow(
                    label: "Bought",
                    value: PeakFormat.usd(boughtUSD),
                    valueSize: 22
                )
                .padding(.bottom, 16)

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
                    valueSize: 36
                )

                HStack(alignment: .firstTextBaseline) {
                    Text(isUp
                         ? "Up \(String(format: "%.1f%%", position.percentPnl))"
                         : "Down \(String(format: "%.1f%%", abs(position.percentPnl)))")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isUp ? PeakPostcard.win : PeakPostcard.loss)
                    Spacer()
                    Text("Now \(PeakFormat.cents(position.currentPrice))")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(PeakPostcard.mute)
                }
                .padding(.top, 14)

                Spacer(minLength: 18)

                HStack(alignment: .center, spacing: 12) {
                    Text(PeakShareDate.postcardStamp())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PeakPostcard.mute)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    PeakShareMarkPill()
                }
            }
        }
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
