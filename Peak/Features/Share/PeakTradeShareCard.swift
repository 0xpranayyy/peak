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

// MARK: - Trade postcard (Luminous Signal)

/// Peak marketing postcard for a completed fill — luminous, asymmetric, not a receipt.
///
/// Stage + paper + real `PeakLogo` brand chrome. Buy reads as mint/win energy;
/// sell as Peak teal luminosity. Renders via `PeakTradeShareCardRenderer`.
struct PeakTradeShareCard: View {
    let result: TradeCelebrationResult
    var icon: UIImage? = nil

    /// Buy = vibrant mint; sell = Peak teal — postcard family, never traffic-light red.
    private var accent: Color {
        result.side.accentIsBuy ? PeakPostcard.win : PeakPostcard.teal
    }

    private var accentBright: Color {
        result.side.accentIsBuy ? PeakPostcard.winBright : PeakPostcard.tealBright
    }

    private var accentDeep: Color {
        result.side.accentIsBuy
            ? Color(red: 0.06, green: 0.36, blue: 0.26)
            : Color(red: 0.06, green: 0.32, blue: 0.28)
    }

    var body: some View {
        ZStack {
            tradeStage

            VStack(spacing: 0) {
                PeakShareBrandHeader()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)

                ZStack(alignment: .topLeading) {
                    luminousPaper

                    // Soft accent rail — asymmetry without a heavy sidebar.
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentBright, accent, accentDeep],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4)
                        .padding(.vertical, 26)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 0) {
                        signalRow

                        Text(result.displayTitle)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(PeakPostcard.ink)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 22)

                        if result.displayTitle != result.marketQuestion {
                            Text(result.marketQuestion)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(PeakPostcard.mute)
                                .lineLimit(2)
                                .padding(.top, 6)
                        }

                        heroAmount
                            .padding(.top, 26)

                        metaLine
                            .padding(.top, 14)

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
                    .padding(.leading, 30)
                    .padding(.trailing, 24)
                    .padding(.vertical, 26)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)
        }
        .frame(width: PeakPostcard.cardWidth, height: PeakPostcard.positionCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Atmosphere

    private var tradeStage: some View {
        ZStack {
            Color(red: 0.02, green: 0.07, blue: 0.07)

            // Wide luminous blooms — readable at thumbnail size on X/IG.
            Ellipse()
                .fill(accentBright.opacity(0.55))
                .frame(width: 340, height: 280)
                .blur(radius: 70)
                .offset(x: -110, y: -160)

            Ellipse()
                .fill(accent.opacity(0.40))
                .frame(width: 300, height: 260)
                .blur(radius: 60)
                .offset(x: 130, y: 180)

            Ellipse()
                .fill(accentDeep.opacity(0.50))
                .frame(width: 220, height: 200)
                .blur(radius: 50)
                .offset(x: 140, y: -120)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.clear,
                    Color.black.opacity(0.42),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private var luminousPaper: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 1.0, blue: 0.995),
                        PeakPostcard.paper,
                        Color(red: 0.94, green: 0.97, blue: 0.96),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentBright.opacity(0.22),
                                accent.opacity(0.08),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: UnitPoint(x: 0.75, y: 0.55)
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.90),
                                accentBright.opacity(0.45),
                                accent.opacity(0.20),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.35
                    )
            }
            .shadow(color: accentBright.opacity(0.35), radius: 28, y: 10)
            .shadow(color: Color.black.opacity(0.38), radius: 30, y: 18)
    }

    // MARK: Content

    /// Polished market tile + luminous verb chip — chip never shares width with the title.
    private var signalRow: some View {
        HStack(alignment: .center, spacing: 14) {
            polishedIcon

            VStack(alignment: .leading, spacing: 8) {
                sideChip
                if result.isPartial {
                    partialBadge
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var polishedIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accentBright.opacity(0.18))
                .frame(width: 72, height: 72)
                .blur(radius: 8)

            PeakShareMarketIcon(image: icon, size: 66, corner: 17)
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.7), accentBright.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
        }
        .shadow(color: accent.opacity(0.32), radius: 14, y: 7)
    }

    private var sideChip: some View {
        HStack(spacing: 7) {
            Text(result.side.pastTitle.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.0)
            Text("·")
                .font(.system(size: 12, weight: .bold))
                .opacity(0.55)
            Text(result.outcomeLabel.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.5)
        }
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentBright, accent, accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: accentBright.opacity(0.55), radius: 12, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.side.pastTitle) \(result.outcomeLabel)")
    }

    private var partialBadge: some View {
        Text("Partial fill")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(accentDeep)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.12))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(accent.opacity(0.35), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
    }

    private var heroAmount: some View {
        Text(PeakFormat.usd(result.usd))
            .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(
                LinearGradient(
                    colors: [accentBright, accent, accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: accentBright.opacity(0.28), radius: 16, y: 5)
            .minimumScaleFactor(0.45)
            .lineLimit(1)
            .accessibilityLabel("Amount \(PeakFormat.usd(result.usd))")
    }

    /// One refined meta line — elegant, not spreadsheet chips.
    private var metaLine: some View {
        HStack(spacing: 0) {
            Text("\(Self.sharesLabel(result.shares)) shares")
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
            Text("  ·  ")
                .font(.system(size: 16, weight: .medium))
                .opacity(0.45)
            Text(PeakFormat.cents(result.price))
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(PeakPostcard.mute)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(accent.opacity(0.08))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(accent.opacity(0.16), lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
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

extension TradeCelebrationResult {
    /// Canvas / preview fixtures — mirrors a typical small fill.
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

#if DEBUG
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
