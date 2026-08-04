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

// MARK: - Trade ticket (boarding-pass share card)

/// Peak marketing share card for a completed fill — train / transit ticket motif.
///
/// Market thumbnail is pre-blurred into a `UIImage` (Core Image) so
/// `ImageRenderer` stays reliable; SwiftUI `blur` is not used for export.
/// Buy reads mint; sell reads Peak teal. Renders via `PeakTradeShareCardRenderer`.
struct PeakTradeShareCard: View {
    let result: TradeCelebrationResult
    var icon: UIImage? = nil
    /// Pre-blurred market art for the ticket field. Prefer baking blur in UIKit /
    /// Core Image — do not rely on SwiftUI `blur` inside `ImageRenderer`.
    var blurredBackground: UIImage? = nil

    private let stubWidth: CGFloat = 78
    private let tearWidth: CGFloat = 18
    private let ticketCorner: CGFloat = 18
    private let notchRadius: CGFloat = 10

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
            stageAtmosphere

            ticket
                .padding(16)
                .shadow(color: accentBright.opacity(0.22), radius: 24, y: 12)
                .shadow(color: Color.black.opacity(0.45), radius: 28, y: 16)
        }
        .frame(width: PeakPostcard.cardWidth, height: PeakPostcard.positionCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Atmosphere

    /// Soft stage without SwiftUI `blur` — ImageRenderer can flatten blurred
    /// layers to black. Market art blur is pre-baked via `PeakShareImageBlur`.
    private var stageAtmosphere: some View {
        ZStack {
            Color(red: 0.02, green: 0.07, blue: 0.07)

            RadialGradient(
                colors: [accentBright.opacity(0.32), Color.clear],
                center: UnitPoint(x: 0.15, y: 0.12),
                startRadius: 10,
                endRadius: 220
            )

            RadialGradient(
                colors: [accent.opacity(0.26), Color.clear],
                center: UnitPoint(x: 0.88, y: 0.86),
                startRadius: 8,
                endRadius: 200
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.clear,
                    Color.black.opacity(0.40),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: Ticket

    private var ticket: some View {
        ZStack {
            ticketField

            HStack(spacing: 0) {
                stubPanel
                    .frame(width: stubWidth)

                tearColumn
                    .frame(width: tearWidth)

                mainPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.vertical, 2)
        }
        .clipShape(PeakTradeTicketShape(stubWidth: stubWidth, tearWidth: tearWidth, corner: ticketCorner, notchRadius: notchRadius))
        .overlay {
            PeakTradeTicketShape(stubWidth: stubWidth, tearWidth: tearWidth, corner: ticketCorner, notchRadius: notchRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            accentBright.opacity(0.35),
                            Color.white.opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
        }
    }

    /// Blurred market art (or Peak stage) as the ticket paper.
    private var ticketField: some View {
        ZStack {
            if let blurredBackground {
                Image(uiImage: blurredBackground)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        accentDeep,
                        PeakPostcard.stage,
                        Color(red: 0.04, green: 0.12, blue: 0.11),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Heavy scrim — keeps boarding-pass type readable on any thumbnail.
            LinearGradient(
                colors: [
                    Color.black.opacity(blurredBackground == nil ? 0.28 : 0.55),
                    Color(red: 0.02, green: 0.08, blue: 0.08).opacity(blurredBackground == nil ? 0.45 : 0.72),
                    Color.black.opacity(blurredBackground == nil ? 0.55 : 0.82),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [accentBright.opacity(0.18), Color.clear, accent.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .allowsHitTesting(false)
    }

    private var stubPanel: some View {
        VStack(spacing: 0) {
            Image("PeakLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }
                .padding(.top, 20)

            Spacer(minLength: 12)

            // Letter stack avoids `rotationEffect`, which is flaky in ImageRenderer.
            VStack(spacing: 3) {
                ForEach(Array(result.side.pastTitle.uppercased().enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(accentBright)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(result.side.pastTitle)

            Spacer(minLength: 12)

            Text(PeakShareDate.compactDay())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.18))
    }

    private var tearColumn: some View {
        ZStack {
            PeakTicketDashLine()
                .stroke(
                    style: StrokeStyle(lineWidth: 1.2, dash: [3.5, 4.5])
                )
                .foregroundStyle(Color.white.opacity(0.28))
                .frame(width: 1)
                .padding(.vertical, notchRadius + 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                sideOutcomeChip

                if result.isPartial {
                    partialBadge
                }

                Spacer(minLength: 0)

                if let icon {
                    PeakShareMarketIcon(image: icon, size: 44, corner: 11)
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        }
                }
            }

            Text("MARKET")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.42))
                .padding(.top, 22)

            Text(result.displayTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.96))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if result.displayTitle != result.marketQuestion {
                Text(result.marketQuestion)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(2)
                    .padding(.top, 5)
            }

            Text(PeakFormat.usd(result.usd))
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, accentBright],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .padding(.top, 22)
                .accessibilityLabel("Amount \(PeakFormat.usd(result.usd))")

            HStack(alignment: .top, spacing: 22) {
                boardingStat(label: "Shares", value: Self.sharesLabel(result.shares))
                boardingStat(label: "Price", value: PeakFormat.cents(result.price))
            }
            .padding(.top, 16)

            Spacer(minLength: 14)

            HStack(alignment: .center, spacing: 10) {
                Text(PeakShareDate.stamp())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                Spacer(minLength: 8)
                PeakShareBrandFooter(trailing: nil, light: false)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .padding(.vertical, 22)
    }

    private var sideOutcomeChip: some View {
        HStack(spacing: 6) {
            Text(result.side.pastTitle.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.9)
            Text("·")
                .font(.system(size: 11, weight: .bold))
                .opacity(0.55)
            Text(result.outcomeLabel.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.4)
        }
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
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

    private func boardingStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.40))
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.90))
        }
    }

    private static func sharesLabel(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() && abs(rounded) < 1_000_000 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
    }
}

// MARK: - Ticket geometry

/// Transit-ticket outline: rounded body + semicircle bites on the tear line.
struct PeakTradeTicketShape: InsettableShape {
    var stubWidth: CGFloat
    var tearWidth: CGFloat
    var corner: CGFloat
    var notchRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = max(0, corner - insetAmount * 0.35)
        let notch = max(0, notchRadius - insetAmount * 0.25)
        let tearX = r.minX + stubWidth + tearWidth * 0.5

        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))

        // Top edge → left of notch
        path.addLine(to: CGPoint(x: tearX - notch, y: r.minY))
        path.addArc(
            center: CGPoint(x: tearX, y: r.minY),
            radius: notch,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )

        // Top-right corner
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addArc(
            center: CGPoint(x: r.maxX - c, y: r.minY + c),
            radius: c,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right → bottom-right
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addArc(
            center: CGPoint(x: r.maxX - c, y: r.maxY - c),
            radius: c,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge → right of notch
        path.addLine(to: CGPoint(x: tearX + notch, y: r.maxY))
        path.addArc(
            center: CGPoint(x: tearX, y: r.maxY),
            radius: notch,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )

        // Bottom-left corner
        path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addArc(
            center: CGPoint(x: r.minX + c, y: r.maxY - c),
            radius: c,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left → top-left
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.addArc(
            center: CGPoint(x: r.minX + c, y: r.minY + c),
            radius: c,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PeakTradeTicketShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Vertical guide for the perforated tear.
private struct PeakTicketDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Blur helper (ImageRenderer-safe)

enum PeakShareImageBlur {
    /// Gaussian-blur a thumbnail for share-card backgrounds. Crops back to the
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
