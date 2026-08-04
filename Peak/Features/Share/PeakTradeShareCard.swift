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

// MARK: - Trade postcard

/// Peak marketing postcard for a completed buy/sell — same paper chrome as market/position cards.
struct PeakTradeShareCard: View {
    let result: TradeCelebrationResult
    var icon: UIImage? = nil

    private var accent: Color {
        result.side.accentIsBuy ? PeakPostcard.win : PeakPostcard.teal
    }

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
                        Text(result.headline.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(accent)

                        HStack(alignment: .top, spacing: 14) {
                            PeakShareMarketIcon(image: icon, size: 52, corner: 12)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.displayTitle)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(PeakPostcard.ink)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)

                                if result.displayTitle != result.marketQuestion {
                                    Text(result.marketQuestion)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(PeakPostcard.mute)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 12)

                        PeakPostcardRule()

                        PeakPostcardStatRow(
                            label: "Side",
                            value: "\(result.side.pastTitle) \(result.outcomeLabel)",
                            valueColor: accent,
                            valueSize: 22
                        )
                        .padding(.bottom, 14)

                        PeakPostcardStatRow(
                            label: "Price",
                            value: PeakFormat.cents(result.price),
                            valueSize: 22
                        )
                        .padding(.bottom, 14)

                        PeakPostcardStatRow(
                            label: "Amount",
                            value: PeakFormat.usd(result.usd),
                            valueSize: 22
                        )

                        PeakPostcardRule()

                        PeakPostcardStatRow(
                            label: "Shares",
                            value: Self.sharesLabel(result.shares),
                            valueColor: PeakPostcard.teal,
                            valueSize: 34
                        )

                        if result.isPartial {
                            Text("Partial fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PeakPostcard.mute)
                                .padding(.top, 10)
                        }

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
