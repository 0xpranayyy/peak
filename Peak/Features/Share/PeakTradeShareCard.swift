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
    /// Profile avatar from `PeakProfileStore` (pre-fetched for ImageRenderer).
    var avatarURL: URL? = nil
    /// Fill time shown on the receipt footer.
    var tradedAt: Date = Date()
    /// Average entry for the shares being closed. Set when a sell is opened from
    /// a known position; `nil` when holdings are unknown (e.g. sell from market).
    var entryPrice: Double? = nil

    var headline: String { side.pastTitle }

    var displayTitle: String {
        if let eventTitle, !eventTitle.isEmpty, eventTitle != marketQuestion {
            return eventTitle
        }
        return marketQuestion
    }

    /// Binary markets pay $1 per share if the outcome wins — max payout on a buy.
    var toWinUSD: Double { shares }

    /// Whether "To win" / payout is meaningful on the share card (buys / open exposure).
    var showsToWin: Bool { side == .buy }

    /// Price as implied odds percent (0–100).
    var impliedOdds: Int {
        Int((price * 100).rounded())
    }

    /// Cost basis of the shares in this fill — needs a known entry price.
    var costBasis: Double? {
        guard let entryPrice, entryPrice > 0 else { return nil }
        return shares * entryPrice
    }

    /// Dollars actually made or lost closing this position.
    var realizedPnl: Double? {
        guard side == .sell, let cost = costBasis else { return nil }
        return usd - cost
    }

    /// Realized return as a percentage of cost basis (38.2 → +38.2%).
    var realizedReturnPct: Double? {
        guard let pnl = realizedPnl, let cost = costBasis, cost > 0 else { return nil }
        return (pnl / cost) * 100
    }

    /// Buy: toWin − spent. Sell: nil (use proceeds-focused copy instead).
    var potentialProfit: Double? {
        guard side == .buy, usd > 0 else { return nil }
        return toWinUSD - usd
    }

    /// Buy: profit / spent × 100. Sell: nil.
    var potentialReturnPct: Double? {
        guard let profit = potentialProfit, usd > 0 else { return nil }
        return (profit / usd) * 100
    }

    /// Shares × $1 for long buys (same as toWin); nil on sells.
    var potentialPayout: Double? {
        showsToWin ? toWinUSD : nil
    }

    /// Deep link when a market slug is known.
    var marketURL: URL? {
        guard let slug = marketSlug?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty else {
            return nil
        }
        return URL(string: "https://app.peakapp.site/event/\(slug)")
    }

    /// Plain display name for the receipt footer (no forced `@`).
    var displayName: String {
        let raw = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Peak trader" : raw
    }

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
        if let profit = potentialProfit {
            lines.append("Potential profit \(PeakFormat.usd(profit))")
        }
        if showsToWin {
            lines.append("Potential payout \(PeakFormat.usd(toWinUSD))")
        }
        if isPartial {
            lines.append("(partial fill)")
        }
        lines.append("")
        lines.append("Trade on Peak")
        return lines.joined(separator: "\n")
    }

    static func formatShares(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() && abs(rounded) < 1_000_000 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
    }
}

// MARK: - Trade receipt share card

/// Peak trade receipt — near-black charcoal with multi-accent color (not teal soup).
///
/// Clear market thumbnail + outcome/odds + hero profit + 3-column fill stats.
/// Ambient blur / topographic wash is pre-baked so `ImageRenderer` stays reliable.
struct PeakTradeShareCard: View {
    let result: TradeCelebrationResult
    var icon: UIImage? = nil
    var avatar: UIImage? = nil
    /// Pre-blurred market art for subtle ambient wash only — not the hero tile.
    var blurredBackground: UIImage? = nil
    /// On-screen reveal choreography. Left `false` for `ImageRenderer` exports.
    var animated: Bool = false

    /// Buy / profit → vivid mint; sell / proceeds → warm coral.
    private var heroColor: Color {
        result.side.accentIsBuy ? PeakPostcard.winBright : PeakPostcard.sellBright
    }

    /// YES → emerald; NO → soft rose; other labels → soft sky.
    private var outcomePillColor: Color {
        let label = result.outcomeLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if label == "yes" || label == "y" { return PeakPostcard.winBright }
        if label == "no" || label == "n" { return PeakPostcard.noRose }
        return PeakPostcard.sky
    }

    var body: some View {
        if PeakReceiptStyle.isEnabled {
            PeakReceiptCard(
                data: PeakReceiptData(trade: result),
                icon: icon,
                avatar: avatar,
                animated: animated
            )
        } else {
            legacyBody
        }
    }

    /// Previous charcoal receipt. Kept intact — `PeakReceiptStyle` flips back to it.
    private var legacyBody: some View {
        ZStack {
            receiptAtmosphere

            receiptContent
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
        }
        .frame(width: PeakPostcard.cardWidth, height: PeakPostcard.tradeCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: Atmosphere

    private var receiptAtmosphere: some View {
        let w = PeakPostcard.cardWidth
        let h = PeakPostcard.tradeCardHeight
        return ZStack {
            PeakPostcard.charcoal

            if let blurredBackground {
                Color.clear
                    .overlay {
                        Image(uiImage: blurredBackground)
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(width: w, height: h)
                    .clipped()
                    .opacity(0.10)
                    .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        PeakPostcard.charcoal.opacity(0.72),
                        PeakPostcard.charcoal.opacity(0.94),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // Soft multi-accent blooms — mint/coral for the trade side, gold + sky depth.
            RadialGradient(
                colors: [heroColor.opacity(0.16), Color.clear],
                center: UnitPoint(x: 0.14, y: 0.06),
                startRadius: 4,
                endRadius: 200
            )
            RadialGradient(
                colors: [PeakPostcard.gold.opacity(0.08), Color.clear],
                center: UnitPoint(x: 0.88, y: 0.90),
                startRadius: 4,
                endRadius: 210
            )
            RadialGradient(
                colors: [PeakPostcard.sky.opacity(0.06), Color.clear],
                center: UnitPoint(x: 0.70, y: 0.22),
                startRadius: 2,
                endRadius: 160
            )

            topographicTexture
                .opacity(0.55)
                .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.06),
                    Color.clear,
                    Color.black.opacity(0.46),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }

    /// Sparse contour wash — cool gray/white, never teal-on-teal.
    private var topographicTexture: some View {
        Canvas { context, size in
            let stroke = Color(red: 0.78, green: 0.82, blue: 0.88).opacity(0.07)
            let centers: [CGPoint] = [
                CGPoint(x: size.width * 0.16, y: size.height * 0.18),
                CGPoint(x: size.width * 0.82, y: size.height * 0.72),
            ]
            for center in centers {
                for i in 1...5 {
                    let r = CGFloat(i) * 44
                    var path = Path()
                    path.addEllipse(in: CGRect(
                        x: center.x - r,
                        y: center.y - r * 0.58,
                        width: r * 2,
                        height: r * 1.16
                    ))
                    context.stroke(path, with: .color(stroke), lineWidth: 0.9)
                }
            }
        }
    }

    // MARK: Content

    private var receiptContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            marketRow
                .padding(.top, 22)

            outcomeAndOdds
                .padding(.top, 14)

            heroBlock
                .padding(.top, 18)

            receiptDivider
                .padding(.top, 20)

            statsColumns
                .padding(.top, 16)

            receiptDivider
                .padding(.top, 16)

            payoutRow
                .padding(.top, 14)

            Spacer(minLength: 12)

            footerRow
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 9) {
                Image("PeakLogo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }

                Text("PEAK")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(Color.white.opacity(0.96))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Peak")

            Spacer(minLength: 8)

            Text(result.isPartial ? "PARTIAL FILL" : "TRADE RECEIPT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.82))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var marketRow: some View {
        HStack(alignment: .top, spacing: 14) {
            PeakShareMarketIcon(image: icon, size: 64, corner: 13)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }

            Text(result.displayTitle)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.white.opacity(0.96))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var outcomeAndOdds: some View {
        HStack(spacing: 10) {
            Text(result.outcomeLabel.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(outcomePillColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(outcomePillColor.opacity(0.12), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(outcomePillColor.opacity(0.72), lineWidth: 1)
                }
                .accessibilityLabel(result.outcomeLabel)

            Text("\(result.impliedOdds)% implied odds")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.52))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var heroBlock: some View {
        if let profit = result.potentialProfit, let ret = result.potentialReturnPct {
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.signedUSD(profit))
                    .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(-0.8)
                    .foregroundStyle(heroColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("\(Self.signedPercent(ret)) potential return")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(heroColor.opacity(0.88))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Potential profit \(Self.signedUSD(profit)), \(Self.signedPercent(ret)) potential return")
        } else {
            // Sells (or zero-cost edge cases): proceeds-focused copy.
            VStack(alignment: .leading, spacing: 6) {
                Text(PeakFormat.usd(result.usd))
                    .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(-0.8)
                    .foregroundStyle(heroColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(result.side == .sell ? "Proceeds" : "Amount")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(heroColor.opacity(0.82))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(result.side == .sell ? "Proceeds" : "Amount") \(PeakFormat.usd(result.usd))")
        }
    }

    private var statsColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            statColumn(
                value: TradeCelebrationResult.formatShares(result.shares),
                label: "\(result.outcomeLabel.uppercased()) SHARES"
            )

            verticalRule

            statColumn(
                value: PeakFormat.cents(result.price),
                label: "AVG. PRICE"
            )

            verticalRule

            statColumn(
                value: PeakFormat.usd(result.usd),
                label: result.side == .buy ? "AMOUNT PAID" : "PROCEEDS"
            )
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(-0.3)
                .foregroundStyle(Color.white.opacity(0.96))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 38)
            .padding(.horizontal, 2)
    }

    private var payoutRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("POTENTIAL PAYOUT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.40))

            Spacer(minLength: 12)

            if let payout = result.potentialPayout {
                Text(PeakFormat.usd(payout))
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(-0.4)
                    .foregroundStyle(Color.white.opacity(0.96))
            } else {
                Text("—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            result.potentialPayout.map { "Potential payout \(PeakFormat.usd($0))" } ?? "Potential payout unavailable"
        )
    }

    private var footerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            receiptAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineLimit(1)
                Text(PeakShareDate.receiptStamp(result.tradedAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.44))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text("View market →")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PeakPostcard.sky)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var receiptAvatar: some View {
        Group {
            if let avatar {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    PeakPostcard.gold.opacity(0.22)
                    Text(Self.initials(result.displayName))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(PeakPostcard.gold)
                }
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(PeakPostcard.gold.opacity(0.55), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }

    /// Edge-faded hairline — cleaner than a hard rule across the card.
    private var receiptDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private static func signedUSD(_ value: Double) -> String {
        let body = PeakFormat.usd(abs(value))
        if value > 0 { return "+\(body)" }
        if value < 0 { return "-\(PeakFormat.usd(abs(value)))" }
        return body
    }

    private static func signedPercent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded > 0 { return "+\(rounded)%" }
        if rounded < 0 { return "\(rounded)%" }
        return "0%"
    }

    private static func initials(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        if trimmed.lowercased().hasPrefix("0x"), trimmed.count >= 4 {
            return String(trimmed.suffix(2)).uppercased()
        }
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
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
    static func image(
        result: TradeCelebrationResult,
        icon: UIImage? = nil,
        avatar: UIImage? = nil
    ) -> UIImage? {
        let blurred = icon.flatMap { PeakShareImageBlur.blurred($0, radius: 34) }
        let card = PeakTradeShareCard(
            result: result,
            icon: icon,
            avatar: avatar,
            blurredBackground: blurred
        )
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(
            width: PeakPostcard.cardWidth,
            height: PeakPostcard.tradeCardHeight
        )
        renderer.scale = 3
        // Ticket notches need alpha; the legacy receipt is unaffected.
        renderer.isOpaque = !PeakReceiptStyle.isEnabled
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
    /// Canvas / preview fixtures — mirrors the trade-receipt prototype numbers.
    static let previewBuy = TradeCelebrationResult(
        side: .buy,
        outcomeLabel: "Yes",
        marketQuestion: "Will ETH close above $4,000 by Aug 31?",
        eventTitle: nil,
        price: 0.42,
        shares: 100,
        usd: 42,
        isPartial: false,
        fillMessage: "Filled",
        marketImageURL: nil,
        marketSlug: "eth-4000-aug-31",
        username: "Mira Chen",
        avatarURL: nil,
        tradedAt: {
            var c = DateComponents()
            c.year = 2026
            c.month = 8
            c.day = 4
            c.hour = 20
            c.minute = 42
            return Calendar.current.date(from: c) ?? Date()
        }()
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
        marketSlug: "fed-cuts-before-sept",
        username: "Mira Chen",
        avatarURL: nil,
        tradedAt: {
            var c = DateComponents()
            c.year = 2026
            c.month = 8
            c.day = 4
            c.hour = 20
            c.minute = 42
            return Calendar.current.date(from: c) ?? Date()
        }()
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

#Preview("Celebration · Sold") {
    TradeCelebrationSheet(result: .previewSell, onDone: {})
}
#endif
