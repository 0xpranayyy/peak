import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

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
    /// Peak / Gamma display name (or email / short wallet fallback).
    let username: String?

    var headline: String { side.pastTitle }

    var displayTitle: String {
        if let eventTitle, !eventTitle.isEmpty, eventTitle != marketQuestion {
            return eventTitle
        }
        return marketQuestion
    }

    /// Binary markets pay $1 per share if the outcome wins — max payout on a buy.
    var toWinUSD: Double { shares }

    /// Whether "To win" is meaningful on the share card (buys / open exposure).
    var showsToWin: Bool { side == .buy }

    /// Footer handle: `@name`, raw email, or truncated wallet — never empty when set.
    var shareHandle: String? {
        guard let raw = username?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.contains("@") { return raw }
        if raw.hasPrefix("0x") { return raw }
        if raw.hasPrefix("@") { return raw }
        return "@\(raw)"
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
        if showsToWin {
            lines.append("To win \(PeakFormat.usd(toWinUSD))")
        }
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

// MARK: - Modern Peak trade share card

/// Premium fintech share card for a completed fill — X / IG story ready.
///
/// Visible market thumbnail + stats grid on Peak teal / mint stage. Optional
/// ambient blur is pre-baked via Core Image so `ImageRenderer` stays reliable
/// (SwiftUI `blur` is not used for export).
struct PeakTradeShareCard: View {
    let result: TradeCelebrationResult
    var icon: UIImage? = nil
    /// Pre-blurred market art for subtle ambient wash only — not the hero tile.
    var blurredBackground: UIImage? = nil

    private var accent: Color {
        result.side.accentIsBuy ? PeakPostcard.win : PeakPostcard.teal
    }

    private var accentBright: Color {
        result.side.accentIsBuy ? PeakPostcard.winBright : PeakPostcard.tealBright
    }

    private var accentDeep: Color {
        result.side.accentIsBuy
            ? Color(red: 0.05, green: 0.32, blue: 0.24)
            : Color(red: 0.05, green: 0.28, blue: 0.26)
    }

    var body: some View {
        // Mirror `PeakPositionShareCard`: one sized ZStack, content padded inside.
        // Nested clipShapes + unbound `scaledToFill` blurs made ImageRenderer
        // center-crop the postcard (clipped badge / SPENT / footer).
        ZStack {
            stageAtmosphere

            cardSurface
                .padding(20)
        }
        .frame(width: PeakPostcard.cardWidth, height: PeakPostcard.tradeCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Atmosphere

    private var stageAtmosphere: some View {
        let w = PeakPostcard.cardWidth
        let h = PeakPostcard.tradeCardHeight
        return ZStack {
            Color(red: 0.02, green: 0.06, blue: 0.07)

            if let blurredBackground {
                // Explicit size — never let `scaledToFill` inflate ideal size.
                Color.clear
                    .overlay {
                        Image(uiImage: blurredBackground)
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(width: w, height: h)
                    .clipped()
                    .opacity(0.38)
                    .allowsHitTesting(false)

                // Keep type readable over any market art.
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.07, blue: 0.07).opacity(0.55),
                        Color(red: 0.02, green: 0.07, blue: 0.07).opacity(0.82),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            RadialGradient(
                colors: [accentBright.opacity(0.34), Color.clear],
                center: UnitPoint(x: 0.12, y: 0.08),
                startRadius: 8,
                endRadius: 240
            )

            RadialGradient(
                colors: [accent.opacity(0.28), Color.clear],
                center: UnitPoint(x: 0.92, y: 0.88),
                startRadius: 6,
                endRadius: 220
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.clear,
                    Color.black.opacity(0.42),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }

    // MARK: Card

    private var cardSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            marketBlock
                .padding(.top, 18)

            statsGrid
                .padding(.top, 18)

            Spacer(minLength: 12)

            footerRow
                .layoutPriority(1)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.04),
                            Color.black.opacity(0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accentDeep.opacity(0.35))
                        .blendMode(.overlay)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            accentBright.opacity(0.40),
                            Color.white.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            PeakShareBrandHeader()
                .layoutPriority(0)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                sideOutcomeChip
                if result.isPartial {
                    partialBadge
                }
            }
            .layoutPriority(1)
        }
    }

    private var marketBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            // Clear, visible thumbnail — not only ambient blur.
            PeakShareMarketIcon(image: icon, size: 64, corner: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text("MARKET")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.42))

                Text(result.displayTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if result.displayTitle != result.marketQuestion {
                    Text(result.marketQuestion)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statChip(
                    label: result.side == .buy ? "Spent" : "Proceeds",
                    value: PeakFormat.usd(result.usd),
                    emphasize: true
                )
                if result.showsToWin {
                    statChip(
                        label: "To win",
                        value: PeakFormat.usd(result.toWinUSD),
                        emphasize: true,
                        valueColor: accentBright
                    )
                }
            }

            HStack(spacing: 10) {
                statChip(label: "Shares", value: Self.sharesLabel(result.shares))
                statChip(label: "Price", value: PeakFormat.cents(result.price))
            }
        }
    }

    private func statChip(
        label: String,
        value: String,
        emphasize: Bool = false,
        valueColor: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
            Text(value)
                .font(
                    .system(
                        size: emphasize ? 20 : 16,
                        weight: emphasize ? .bold : .semibold,
                        design: .rounded
                    )
                    .monospacedDigit()
                )
                .foregroundStyle(valueColor ?? Color.white.opacity(emphasize ? 0.98 : 0.90))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    private var footerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(PeakShareDate.stamp())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let handle = result.shareHandle {
                    Text(handle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            PeakShareBrandFooter(trailing: nil, light: false)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var sideOutcomeChip: some View {
        HStack(spacing: 4) {
            Text(result.side.pastTitle.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
            Text("·")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.55)
            Text(result.outcomeLabel.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.2)
        }
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
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
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.side.pastTitle) \(result.outcomeLabel)")
    }

    private var partialBadge: some View {
        Text("Partial")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(accentBright)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(accentBright.opacity(0.45), lineWidth: 1)
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

// MARK: - Blur helper (ImageRenderer-safe)

enum PeakShareImageBlur {
    /// Gaussian-blur a thumbnail for share-card ambient. Crops back to the
    /// source extent after clamping so edges don't go transparent.
    static func blurred(_ image: UIImage, radius: CGFloat = 32) -> UIImage? {
        guard let cgImage = image.cgImage else { return softFallbackBlur(image, radius: radius) }
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ciImage.clampedToExtent()
        filter.radius = Float(radius)
        guard let output = filter.outputImage?.cropped(to: ciImage.extent) else {
            return softFallbackBlur(image, radius: radius)
        }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let outCG = context.createCGImage(output, from: output.extent) else {
            return softFallbackBlur(image, radius: radius)
        }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: image.imageOrientation)
    }

    /// UIKit downscale fallback when Core Image is unavailable.
    private static func softFallbackBlur(_ image: UIImage, radius: CGFloat) -> UIImage? {
        let scale = max(0.08, min(0.28, 12 / max(radius, 1)))
        let size = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let tiny = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let fullFormat = UIGraphicsImageRendererFormat()
        fullFormat.scale = image.scale
        fullFormat.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: fullFormat).image { _ in
            tiny.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

// MARK: - Renderer + X helpers

enum PeakTradeShareCardRenderer {
    @MainActor
    static func image(result: TradeCelebrationResult, icon: UIImage? = nil) -> UIImage? {
        let blurred = icon.flatMap { PeakShareImageBlur.blurred($0, radius: 34) }
        let card = PeakTradeShareCard(result: result, icon: icon, blurredBackground: blurred)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(
            width: PeakPostcard.cardWidth,
            height: PeakPostcard.tradeCardHeight
        )
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
        marketSlug: "btc-150k-2026",
        username: "peaktrader"
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
        marketSlug: nil,
        username: "peaktrader"
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
