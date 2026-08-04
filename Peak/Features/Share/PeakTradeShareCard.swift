import SwiftUI
import UIKit

/// Snapshot of a completed fill — drives celebration UI and the share postcard.
struct TradeCelebrationResult: Equatable, Sendable {
    enum Side: String, Equatable, Sendable {
        case buy
        case sell

        var pastTitle: String {
            switch self {
            case .buy: return "Bought"
            case .sell: return "Sold"
            }
        }

        var verb: String {
            switch self {
            case .buy: return "bought"
            case .sell: return "sold"
            }
        }

        var accentIsBuy: Bool { self == .buy }
    }

    let side: Side
    let outcomeLabel: String
    let marketQuestion: String
    let eventTitle: String?
    let price: Double
    let shares: Double
    let usd: Double
    let isPartial: Bool
    let fillMessage: String
    let marketImageURL: URL?
    let marketSlug: String?

    var headline: String { side.pastTitle }

    var displayTitle: String {
        if let eventTitle, !eventTitle.isEmpty, eventTitle != marketQuestion {
            return eventTitle
        }
        return marketQuestion
    }

    var tweetText: String {
        let cents = PeakFormat.cents(price)
        let amount = PeakFormat.usd(usd)
        let sharesText = Self.formatShares(shares)
        var lines = [
            "Just \(side.verb) \(outcomeLabel) on Peak",
            "",
            displayTitle,
            "\(amount) · \(sharesText) shares @ \(cents)",
        ]
        if isPartial {
            lines.append("(partial fill)")
        }
        lines.append("")
        lines.append("Trade on Peak")
        return lines.joined(separator: "\n")
    }

    private static func formatShares(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() && abs(rounded) < 1_000_000 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
    }
}

// MARK: - Trade postcard (Hero Signal)

/// Peak marketing postcard for a completed fill — one giant signal, not a receipt.
///
/// Keeps the market/position postcard family (stage + paper + `PeakLogo` brand
/// header) but elevates hierarchy: verb chip, hero USD, one compact stats line.
struct PeakTradeShareCard: View {
    let result: TradeCelebrationResult
    var icon: UIImage? = nil

    /// Buy = win green; sell = Peak teal — postcard tokens, not traffic-light red.
    private var accent: Color {
        result.side.accentIsBuy ? PeakPostcard.win : PeakPostcard.teal
    }

    private var accentBright: Color {
        result.side.accentIsBuy
            ? Color(red: 0.18, green: 0.62, blue: 0.46)
            : PeakPostcard.tealBright
    }

    var body: some View {
        ZStack {
            tradeStage

            VStack(spacing: 0) {
                PeakShareBrandHeader()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)

                ZStack {
                    PeakPostcardPaper()

                    // Soft side wash — tinted by buy/sell without cluttering the paper.
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.16),
                                    accent.opacity(0.05),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: UnitPoint(x: 0.55, y: 0.55)
                            )
                        )
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 0) {
                        marketRow

                        sideChip
                            .padding(.top, 16)

                        heroAmount
                            .padding(.top, 22)

                        compactStats
                            .padding(.top, 10)

                        if result.isPartial {
                            Text("Partial fill")
                                .font(.caption.weight(.semibold))
                                .tracking(0.4)
                                .foregroundStyle(PeakPostcard.mute)
                                .padding(.top, 12)
                        }

                        Spacer(minLength: 18)

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

    // MARK: Atmosphere

    /// Stage keyed to the fill side — same Peak depth language as market cards,
    /// with a stronger buy/sell glow so the thumb nail reads instantly.
    private var tradeStage: some View {
        ZStack {
            PeakPostcardStage()

            RadialGradient(
                colors: [accent.opacity(0.34), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 340
            )

            RadialGradient(
                colors: [accentBright.opacity(0.22), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 280
            )
        }
    }

    // MARK: Content

    private var marketRow: some View {
        HStack(alignment: .top, spacing: 14) {
            PeakShareMarketIcon(image: icon, size: 56, corner: 13)

            VStack(alignment: .leading, spacing: 5) {
                Text(result.displayTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PeakPostcard.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if result.displayTitle != result.marketQuestion {
                    Text(result.marketQuestion)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PeakPostcard.mute)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Strong verb + outcome — the glanceable “what happened” stamp.
    private var sideChip: some View {
        HStack(spacing: 7) {
            Text(result.side.pastTitle.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
            Text("·")
                .font(.caption.weight(.bold))
                .opacity(0.55)
            Text(result.outcomeLabel.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent, accentBright],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.side.pastTitle) \(result.outcomeLabel)")
    }

    private var heroAmount: some View {
        Text(PeakFormat.usd(result.usd))
            .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(accent)
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .accessibilityLabel("Amount \(PeakFormat.usd(result.usd))")
    }

    /// One quiet secondary line — shares + entry price, not four receipt rows.
    private var compactStats: some View {
        Text("\(Self.sharesLabel(result.shares)) shares · \(PeakFormat.cents(result.price))")
            .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(PeakPostcard.mute)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private static func sharesLabel(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() && abs(rounded) < 1_000_000 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
    }
}

// MARK: - Renderer + X helpers

enum PeakTradeShareCardRenderer {
    @MainActor
    static func image(result: TradeCelebrationResult, icon: UIImage? = nil) -> UIImage? {
        let card = PeakTradeShareCard(result: result, icon: icon)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    static func loadIcon(url: URL?) async -> UIImage? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return UIImage(data: data)
    }
}

enum PeakXShare {
    /// Opens the X app compose sheet when installed; otherwise the web intent.
    /// Image attachment is not supported by the intent URL — callers should
    /// also offer the system share sheet for the trade card image.
    @MainActor
    static func openCompose(text: String) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let appURLs = [
            URL(string: "twitter://post?message=\(encoded)"),
            URL(string: "twitter-x://post?message=\(encoded)"),
        ].compactMap { $0 }

        for url in appURLs where UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        if let web = URL(string: "https://twitter.com/intent/tweet?text=\(encoded)") {
            UIApplication.shared.open(web)
        }
    }
}

/// Bridges SwiftUI → `UIActivityViewController` for image + text shares.
struct PeakActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
extension TradeCelebrationResult {
    /// Canvas / DEBUG fixtures — mirrors a typical small fill.
    static let previewBuy = TradeCelebrationResult(
        side: .buy,
        outcomeLabel: "Yes",
        marketQuestion: "Will BTC hit $150k in 2026?",
        eventTitle: "Bitcoin above $150,000 by Dec 31?",
        price: 0.42,
        shares: 48,
        usd: 20.16,
        isPartial: false,
        fillMessage: "Filled",
        marketImageURL: nil,
        marketSlug: "btc-150k-2026"
    )

    static let previewSell = TradeCelebrationResult(
        side: .sell,
        outcomeLabel: "No",
        marketQuestion: "Fed cuts rates before September?",
        eventTitle: nil,
        price: 0.61,
        shares: 15.5,
        usd: 9.46,
        isPartial: true,
        fillMessage: "Partial fill",
        marketImageURL: nil,
        marketSlug: nil
    )
}

#Preview("Trade card · Bought") {
    PeakTradeShareCard(result: .previewBuy)
        .padding(24)
        .background(Color.black)
}

#Preview("Trade card · Sold") {
    PeakTradeShareCard(result: .previewSell)
        .padding(24)
        .background(Color.black)
}

#Preview("Celebration · Bought") {
    TradeCelebrationSheet(result: .previewBuy, onDone: {})
}
#endif
