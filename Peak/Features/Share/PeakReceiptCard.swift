import SwiftUI
import UIKit

// MARK: - Rollback switch

/// Single switch between the new receipt art and the previous share cards.
///
/// Flip `defaultsToNewReceipt` to `false` (or set the `peak.receipt.v2` user
/// default) to restore the old `PeakTradeShareCard` / `PeakPositionShareCard`
/// bodies with no other code changes.
enum PeakReceiptStyle {
    private static let defaultsKey = "peak.receipt.v2"
    private static let defaultsToNewReceipt = true

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) != nil {
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        return defaultsToNewReceipt
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
}

// MARK: - Receipt view model

/// One cell in the receipt's three-column stat grid.
struct PeakReceiptStat: Identifiable {
    var id: String { key }
    var key: String
    var value: String
    var isAccent: Bool = false

    init(_ key: String, _ value: String, accent: Bool = false) {
        self.key = key
        self.value = value
        self.isAccent = accent
    }
}

/// Everything the receipt renders. Built from a fill (`TradeCelebrationResult`)
/// or an open/settled position (`PortfolioPosition`) — the card itself never
/// touches those types, so either source can change without breaking the art.
struct PeakReceiptData {
    enum Status {
        case open
        case filled(partial: Bool)
        case closed(partial: Bool)
        case won
        case lost

        var isSettled: Bool {
            switch self {
            case .won, .lost: return true
            case .open, .filled, .closed: return false
            }
        }

        var label: String {
            switch self {
            case .open: return "POSITION OPEN"
            case .filled(let partial): return partial ? "PARTIAL FILL" : "FILLED"
            case .closed(let partial): return partial ? "PARTIAL CLOSE" : "CLOSED"
            case .won: return "SETTLED · WON"
            case .lost: return "SETTLED · LOST"
            }
        }
    }

    /// Market question, shown small above the pick.
    var marketTitle: String
    /// The outcome taken, shown huge.
    var outcomeLabel: String
    /// "BOUGHT · YES" style tag under the pick.
    var sideTag: String
    var status: Status

    /// How the hero number should be formatted while counting up.
    enum HeroStyle {
        case percent
        case usd
    }

    /// Hero number, already formatted. Usually a signed percentage.
    var heroValue: String
    /// Raw value behind `heroValue`, for the count-up. `nil` skips counting.
    var heroNumeric: Double?
    var heroStyle: HeroStyle
    var heroCaption: String
    /// Small "from → to" line beside the hero. `nil` hides it.
    var heroFrom: String?
    var heroTo: String?

    /// Three stat cells shown in the grid.
    var stats: [PeakReceiptStat]

    var footerKey: String
    var footerValue: String

    /// 0...1 price series, oldest → newest. `nil` swaps in the odds bar.
    var priceHistory: [Double]?
    var entryIndex: Int
    /// Chart caption and the current price readout.
    var chartLabel: String
    var chartValue: String
    /// Drives the odds bar when there is no history.
    var impliedOdds: Double

    var handle: String
    var timestamp: Date
    var referenceLabel: String
    var referenceValue: String
    var qrPayload: String?

    /// `true` for YES-flavoured outcomes; picks the palette on entries.
    var isPositiveOutcome: Bool
    /// `true` when this receipt closes a position. Exits get their own palette.
    var isExit: Bool = false
    /// For exits with a known cost basis: did the user actually make money?
    /// `nil` when there is no basis to compare against.
    var exitProfitable: Bool? = nil
}

// MARK: - Palette

struct PeakReceiptPalette {
    var accent: Color
    var accentHigh: Color
    var accentLow: Color
    var glowA: Color
    var glowB: Color

    var chipFill: Color { accent.opacity(0.10) }
    var chipStroke: Color { accent.opacity(0.24) }
    var textGlow: Color { accent.opacity(0.30) }

    var heroGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: accentHigh, location: 0.00),
                .init(color: accent, location: 0.62),
                .init(color: accentLow, location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Aurora — cyan / indigo. Open or filled YES exposure.
    static let aurora = PeakReceiptPalette(
        accent: Color(red: 0.357, green: 0.910, blue: 1.000),
        accentHigh: Color(red: 0.847, green: 0.984, blue: 1.000),
        accentLow: Color(red: 0.122, green: 0.549, blue: 1.000),
        glowA: Color(red: 0.149, green: 0.627, blue: 1.000).opacity(0.50),
        glowB: Color(red: 0.494, green: 0.282, blue: 1.000).opacity(0.40)
    )

    /// Ember — amber / magenta. Open or filled NO exposure.
    static let ember = PeakReceiptPalette(
        accent: Color(red: 1.000, green: 0.714, blue: 0.357),
        accentHigh: Color(red: 1.000, green: 0.914, blue: 0.780),
        accentLow: Color(red: 1.000, green: 0.416, blue: 0.173),
        glowA: Color(red: 1.000, green: 0.541, blue: 0.173).opacity(0.45),
        glowB: Color(red: 0.769, green: 0.235, blue: 0.471).opacity(0.38)
    )

    /// Summit — mint / emerald. Settled wins.
    static let summit = PeakReceiptPalette(
        accent: Color(red: 0.239, green: 1.000, blue: 0.671),
        accentHigh: Color(red: 0.788, green: 1.000, blue: 0.902),
        accentLow: Color(red: 0.000, green: 0.722, blue: 0.396),
        glowA: Color(red: 0.000, green: 0.839, blue: 0.478).opacity(0.55),
        glowB: Color(red: 0.251, green: 0.353, blue: 1.000).opacity(0.34)
    )

    /// Dusk — rose / slate. Settled losses. Deliberately quieter.
    static let dusk = PeakReceiptPalette(
        accent: Color(red: 1.000, green: 0.420, blue: 0.518),
        accentHigh: Color(red: 1.000, green: 0.827, blue: 0.859),
        accentLow: Color(red: 0.769, green: 0.071, blue: 0.247),
        glowA: Color(red: 0.839, green: 0.102, blue: 0.290).opacity(0.40),
        glowB: Color(red: 0.275, green: 0.275, blue: 0.431).opacity(0.42)
    )

    /// Gilt — gold / violet. Exits. Reads as "cashed out", never as a loss.
    static let gilt = PeakReceiptPalette(
        accent: Color(red: 1.000, green: 0.831, blue: 0.416),
        accentHigh: Color(red: 1.000, green: 0.961, blue: 0.851),
        accentLow: Color(red: 0.831, green: 0.463, blue: 0.145),
        glowA: Color(red: 0.945, green: 0.702, blue: 0.235).opacity(0.44),
        glowB: Color(red: 0.451, green: 0.239, blue: 0.784).opacity(0.46)
    )

    static func palette(for data: PeakReceiptData) -> PeakReceiptPalette {
        switch data.status {
        case .won: return .summit
        case .lost: return .dusk
        case .closed:
            // A losing exit in celebratory gold reads wrong — send it to Dusk.
            return data.exitProfitable == false ? .dusk : .gilt
        case .open, .filled:
            if data.isExit { return .gilt }
            return data.isPositiveOutcome ? .aurora : .ember
        }
    }
}

// MARK: - Metrics

/// All geometry in one place — retune the card without hunting through the view.
enum PeakReceiptMetrics {
    static var W: CGFloat { PeakPostcard.cardWidth }        // 390
    static var H: CGFloat { PeakPostcard.tradeCardHeight }  // 580

    static let pad: CGFloat = 26
    static let corner: CGFloat = PeakPostcard.shellCorner   // 28
    static let notchY: CGFloat = 480
    static let notchR: CGFloat = 13
    static var inner: CGFloat { W - pad * 2 }

    static let ink = Color(red: 0.027, green: 0.027, blue: 0.039)
    static let cellInk = Color(red: 0.043, green: 0.043, blue: 0.059)
    static let textMid = Color(red: 0.839, green: 0.839, blue: 0.878)
    static let textMute = Color(red: 0.514, green: 0.514, blue: 0.561)
    static let textDim = Color(red: 0.357, green: 0.357, blue: 0.408)
    static let textFaint = Color(red: 0.369, green: 0.369, blue: 0.420)
    static let arrow = Color(red: 0.353, green: 0.353, blue: 0.400)
    static let idText = Color(red: 0.788, green: 0.788, blue: 0.831)
    static let avatarWell = Color(red: 0.082, green: 0.082, blue: 0.106)
    static let avatarGlyph = Color(red: 0.286, green: 0.286, blue: 0.341)
}

// MARK: - Ticket shape

/// Rounded rect with circular notches punched into both side edges.
struct PeakReceiptTicketShape: Shape {
    var corner: CGFloat = PeakReceiptMetrics.corner
    var notchRadius: CGFloat = PeakReceiptMetrics.notchR
    var notchY: CGFloat = PeakReceiptMetrics.notchY

    func path(in rect: CGRect) -> Path {
        let base = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
        let cy = rect.minY + notchY
        let left = Path(ellipseIn: CGRect(x: rect.minX - notchRadius,
                                          y: cy - notchRadius,
                                          width: notchRadius * 2,
                                          height: notchRadius * 2))
        let right = Path(ellipseIn: CGRect(x: rect.maxX - notchRadius,
                                           y: cy - notchRadius,
                                           width: notchRadius * 2,
                                           height: notchRadius * 2))
        return base.subtracting(left).subtracting(right)
    }
}

// MARK: - Sparkline

struct PeakReceiptSparkline: View {
    let series: [Double]
    let entryIndex: Int
    let accent: Color

    private let inset: CGFloat = 12
    private let topInset: CGFloat = 30
    private let bottomInset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                let line = smoothed(pts)
                let entry = pts[min(max(entryIndex, 0), pts.count - 1)]
                let head = pts[pts.count - 1]

                ZStack {
                    area(from: line, in: geo.size, first: pts[0], last: head)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.34), accent.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    line.stroke(accent.opacity(0.45),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .blur(radius: 3)

                    line.stroke(
                        LinearGradient(colors: [accent.opacity(0.35), accent],
                                       startPoint: .leading,
                                       endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )

                    Path { p in
                        p.move(to: CGPoint(x: entry.x, y: topInset - 8))
                        p.addLine(to: CGPoint(x: entry.x, y: geo.size.height))
                    }
                    .stroke(Color.white.opacity(0.16),
                            style: StrokeStyle(lineWidth: 0.8, dash: [3, 3.5]))

                    Circle().fill(accent.opacity(0.22))
                        .frame(width: 10, height: 10).position(entry)
                    Circle().fill(PeakReceiptMetrics.ink)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(accent, lineWidth: 1.6))
                        .position(entry)

                    Circle().fill(accent.opacity(0.18))
                        .frame(width: 13, height: 13).position(head)
                    Circle().fill(accent)
                        .frame(width: 5.5, height: 5.5).position(head)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard series.count > 1 else { return [] }
        let lo = series.min() ?? 0
        let hi = series.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let top = topInset
        let bottom = size.height - bottomInset
        return series.enumerated().map { index, value in
            let x = inset + (CGFloat(index) / CGFloat(series.count - 1)) * (size.width - inset * 2)
            let y = bottom - CGFloat((value - lo) / span) * (bottom - top)
            return CGPoint(x: x, y: y)
        }
    }

    private func smoothed(_ pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])
        for index in 1..<pts.count {
            let previous = pts[index - 1]
            let current = pts[index]
            let midX = (previous.x + current.x) / 2
            path.addCurve(to: current,
                          control1: CGPoint(x: midX, y: previous.y),
                          control2: CGPoint(x: midX, y: current.y))
        }
        return path
    }

    private func area(from line: Path, in size: CGSize, first: CGPoint, last: CGPoint) -> Path {
        var path = line
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// Fallback when no price history exists — an honest odds bar instead of a fake chart.
private struct PeakReceiptOddsBar: View {
    let odds: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 24
            let filled = width * CGFloat(min(max(odds, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                    .frame(width: width, height: 10)
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.55), accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(filled, 10), height: 10)
                    .shadow(color: accent.opacity(0.45), radius: 6)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .padding(.leading, 12)
            .offset(y: 12)
        }
    }
}

// MARK: - Count-up

/// Text that interpolates its number frame-by-frame. `Animatable` is what makes
/// SwiftUI re-run `body` on every tick — a plain `@State` Double would not.
private struct PeakCountingNumber: View, Animatable {
    var value: Double
    var style: PeakReceiptData.HeroStyle

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(style == .percent
             ? PeakReceiptFormat.signedPercent(value)
             : PeakFormat.usd(value))
    }
}

// MARK: - The card

/// Peak trade receipt — obsidian ticket stub in an aurora, with a punched tear line.
struct PeakReceiptCard: View {
    let data: PeakReceiptData
    /// Optional market artwork for the emblem tile.
    var icon: UIImage?
    var avatar: UIImage?
    /// Reveal choreography. MUST stay `false` for `ImageRenderer` — a snapshot
    /// never runs `onAppear`, so an animating card would export mid-flight.
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var palette: PeakReceiptPalette { PeakReceiptPalette.palette(for: data) }

    /// Final state unless we are explicitly animating on screen.
    private var shown: Bool { animated ? revealed : true }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
            tearLine
            if data.status.isSettled { stamp }
            footer
        }
        .frame(width: PeakReceiptMetrics.W, height: PeakReceiptMetrics.H)
        .compositingGroup()
        .clipShape(PeakReceiptTicketShape())
        .overlay(
            PeakReceiptTicketShape()
                .stroke(
                    LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 2
                )
                .clipShape(PeakReceiptTicketShape())
        )
        .onAppear(perform: startReveal)
    }

    private func startReveal() {
        guard animated, !revealed else { return }
        guard !reduceMotion else {
            revealed = true
            return
        }
        withAnimation(.easeOut(duration: 0.45)) { revealed = true }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            PeakReceiptMetrics.ink

            Circle()
                .fill(palette.glowA)
                .frame(width: 320, height: 320)
                .blur(radius: 54)
                .offset(x: 126, y: -202)

            Circle()
                .fill(palette.glowB)
                .frame(width: 296, height: 296)
                .blur(radius: 54)
                .offset(x: -148, y: 224)

            Ellipse()
                .fill(palette.glowA.opacity(0.30))
                .frame(width: 252, height: 188)
                .blur(radius: 54)
                .offset(y: 10)

            RadialGradient(colors: [.clear, Color.black.opacity(0.72)],
                           center: UnitPoint(x: 0.5, y: 0.4),
                           startRadius: 116,
                           endRadius: 330)

            PeakMarkShape()
                .fill(Color.white.opacity(0.055))
                .frame(width: 426, height: 224)
                .offset(y: 196)

            LinearGradient(colors: [Color.white.opacity(0.07), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 188)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: PeakReceiptMetrics.W, height: PeakReceiptMetrics.H)
    }

    // MARK: Upper half

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            marketLine.padding(.top, 20)
            pick.padding(.top, 14)
            hero.padding(.top, 14)
            chart.padding(.top, 12)
            statGrid.padding(.top, 10)
            footerBar.padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PeakReceiptMetrics.pad)
        .padding(.top, PeakReceiptMetrics.pad)
        .frame(width: PeakReceiptMetrics.W, height: PeakReceiptMetrics.notchY, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                PeakMarkShape()
                    .fill(Color.white)
                    .frame(width: 17, height: 14)
                Text("PEAK")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: palette.accent, radius: 3)
                Text(data.status.label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(palette.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(palette.chipFill))
            .overlay(Capsule().strokeBorder(palette.chipStroke, lineWidth: 1))
        }
    }

    private var marketLine: some View {
        Text(data.marketTitle)
            .font(.system(size: 13, weight: .medium))
            .lineSpacing(3)
            .lineLimit(2)
            .foregroundStyle(PeakReceiptMetrics.textMute)
            .frame(width: PeakReceiptMetrics.inner * 0.86, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var pick: some View {
        HStack(alignment: .center, spacing: 11) {
            emblem
            VStack(alignment: .leading, spacing: 7) {
                Text(data.outcomeLabel)
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)

                Text(data.sideTag)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.chipFill)
                    )
            }
        }
    }

    private var emblem: some View {
        Group {
            if let icon {
                Image(uiImage: icon).resizable().scaledToFill()
            } else {
                Text(String(data.outcomeLabel.prefix(1)).uppercased())
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(width: 38, height: 38)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 9, y: 7)
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ZStack(alignment: .leading) {
                // Reserves the final width so the count-up never reflows the row.
                Text(data.heroValue).hidden()
                if let numeric = data.heroNumeric, animated {
                    PeakCountingNumber(value: shown ? numeric : 0, style: data.heroStyle)
                } else {
                    Text(data.heroValue)
                }
            }
            .font(.system(size: 56, weight: .black))
            .monospacedDigit()
            .tracking(-2.9)
            .foregroundStyle(palette.heroGradient)
            .shadow(color: palette.textGlow, radius: 15, y: 4)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize()

            VStack(alignment: .leading, spacing: 5) {
                Text(data.heroCaption)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(PeakReceiptMetrics.textDim)
                if let from = data.heroFrom, let to = data.heroTo {
                    HStack(spacing: 4) {
                        Text(from)
                        Text("→").foregroundStyle(PeakReceiptMetrics.arrow)
                        Text(to)
                    }
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PeakReceiptMetrics.textMid)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
            .padding(.bottom, 6)

            Spacer(minLength: 0)
        }
    }

    private var chart: some View {
        ZStack(alignment: .top) {
            if let history = data.priceHistory, history.count > 1 {
                PeakReceiptSparkline(series: history,
                                     entryIndex: data.entryIndex,
                                     accent: palette.accent)
            } else {
                PeakReceiptOddsBar(odds: data.impliedOdds, accent: palette.accent)
            }

            HStack {
                Text(data.chartLabel)
                    .foregroundStyle(PeakReceiptMetrics.textFaint)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(data.chartValue)
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
        .frame(width: PeakReceiptMetrics.inner, height: 74)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statGrid: some View {
        HStack(spacing: 1) {
            ForEach(Array(data.stats.enumerated()), id: \.element.id) { pair in
                let cell = pair.element
                VStack(alignment: .leading, spacing: 6) {
                    Text(cell.key)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(PeakReceiptMetrics.textDim)
                    Text(cell.value)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(cell.isAccent ? palette.accent : Color.white)
                }
                .padding(.horizontal, 11)
                .padding(.top, 11)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PeakReceiptMetrics.cellInk)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 8)
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(response: 0.42, dampingFraction: 0.82)
                            .delay(0.10 + Double(pair.offset) * 0.04),
                    value: shown
                )
            }
        }
        .frame(width: PeakReceiptMetrics.inner)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Text(data.footerKey)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.42))
            Spacer(minLength: 0)
            Text(data.footerValue)
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.4)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(palette.accent)
                .shadow(color: palette.textGlow, radius: 11)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: PeakReceiptMetrics.inner)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.chipFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.chipStroke, lineWidth: 1)
        )
    }

    // MARK: Tear + stamp

    private var tearLine: some View {
        Path { path in
            path.move(to: CGPoint(x: PeakReceiptMetrics.notchR + 3, y: PeakReceiptMetrics.notchY))
            path.addLine(to: CGPoint(x: PeakReceiptMetrics.W - PeakReceiptMetrics.notchR - 3, y: PeakReceiptMetrics.notchY))
        }
        .trim(from: 0, to: shown ? 1 : 0)
        .stroke(Color.white.opacity(0.13),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [5, 5.5]))
        .frame(width: PeakReceiptMetrics.W, height: PeakReceiptMetrics.H)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.16), value: shown)
    }

    private var stamp: some View {
        Group {
            switch data.status {
            case .won: stampBadge("WON")
            case .lost: stampBadge("LOST")
            default: EmptyView()
            }
        }
    }

    private func stampBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 27, weight: .black))
            .tracking(1.5)
            .foregroundStyle(palette.accent)
            .shadow(color: palette.textGlow, radius: 9)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.accent, lineWidth: 2.5)
            )
            .rotationEffect(.degrees(-13))
            .opacity(shown ? 0.92 : 0)
            .scaleEffect(shown ? 1 : 1.55)
            .animation(
                reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.55).delay(0.30),
                value: shown
            )
            .shadow(color: palette.textGlow, radius: 16)
            .padding(.trailing, 24)
            .padding(.top, 284)
            .frame(width: PeakReceiptMetrics.W, height: PeakReceiptMetrics.H, alignment: .topTrailing)
    }

    // MARK: Lower half

    private var footer: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                avatarView
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.handle)
                        .font(.system(size: 14, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                    Text(PeakShareDate.postcardStamp(data.timestamp))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(PeakReceiptMetrics.textFaint)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(data.referenceLabel)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(PeakReceiptMetrics.textDim)
                    Text(data.referenceValue)
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(PeakReceiptMetrics.idText)
                }
                qrTile
            }
        }
        .padding(.horizontal, PeakReceiptMetrics.pad)
        .frame(width: PeakReceiptMetrics.W, height: PeakReceiptMetrics.H - PeakReceiptMetrics.notchY)
        .frame(width: PeakReceiptMetrics.W, height: PeakReceiptMetrics.H, alignment: .bottom)
    }

    @ViewBuilder
    private var qrTile: some View {
        if let payload = data.qrPayload,
           let code = PeakQRCode.image(from: payload, moduleScale: 12) {
            Image(uiImage: code)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white)
                )
        }
    }

    private var avatarView: some View {
        Group {
            if let avatar {
                Image(uiImage: avatar).resizable().scaledToFill()
            } else {
                ZStack {
                    PeakReceiptMetrics.avatarWell
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(PeakReceiptMetrics.avatarGlyph)
                }
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .padding(1.5)
        .background(
            Circle().fill(
                AngularGradient(
                    colors: [palette.accent, palette.accentLow, palette.accentHigh, palette.accent],
                    center: .center,
                    angle: .degrees(210)
                )
            )
        )
    }
}

// MARK: - Adapters

extension PeakReceiptData {
    /// Fresh fill → receipt.
    ///
    /// Buys lead with potential return. Sells lead with realized return when the
    /// entry price is known, otherwise with proceeds. Every number appears once.
    init(trade result: TradeCelebrationResult) {
        let outcome = result.outcomeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = outcome.lowercased()
        let label = outcome.isEmpty ? "Position" : outcome
        let positive = !(lowered == "no" || lowered == "n")
        let isSell = result.side == .sell
        let sharesText = TradeCelebrationResult.formatShares(result.shares)

        let hero: String
        var heroRaw: Double? = nil
        var heroKind: PeakReceiptData.HeroStyle = .percent
        let heroCaption: String
        let from: String?
        let to: String?
        let cells: [PeakReceiptStat]
        let barKey: String
        let barValue: String
        let chartKey: String
        let chartText: String
        var profitable: Bool? = nil

        if isSell {
            if let pct = result.realizedReturnPct, let cost = result.costBasis {
                hero = PeakReceiptFormat.signedPercent(pct)
                heroRaw = pct
                heroCaption = "REALIZED RETURN"
                from = PeakFormat.usd(cost)
                to = PeakFormat.usd(result.usd)
                barKey = "REALIZED P&L"
                barValue = PeakReceiptFormat.signedUSD(result.realizedPnl ?? 0)
                profitable = (result.realizedPnl ?? 0) >= 0
                cells = [
                    PeakReceiptStat("ENTRY", PeakFormat.cents(result.entryPrice ?? 0)),
                    PeakReceiptStat("EXIT", PeakFormat.cents(result.price)),
                    PeakReceiptStat("PROCEEDS", PeakFormat.usd(result.usd), accent: true),
                ]
                chartKey = "ENTRY → EXIT"
                chartText = "\(PeakFormat.cents(result.entryPrice ?? 0)) → \(PeakFormat.cents(result.price))"
            } else {
                // Sold from a market with unknown holdings — no cost basis to compare.
                hero = PeakFormat.usd(result.usd)
                heroRaw = result.usd
                heroKind = .usd
                heroCaption = "PROCEEDS"
                from = nil
                to = nil
                barKey = "EXIT PRICE"
                barValue = PeakFormat.cents(result.price)
                cells = [
                    PeakReceiptStat("EXIT", PeakFormat.cents(result.price)),
                    PeakReceiptStat("SHARES", sharesText),
                    PeakReceiptStat("PROCEEDS", PeakFormat.usd(result.usd), accent: true),
                ]
                chartKey = "\(label.uppercased()) · EXIT PRICE"
                chartText = PeakFormat.cents(result.price)
            }
        } else {
            hero = PeakReceiptFormat.signedPercent(result.potentialReturnPct ?? 0)
            heroRaw = result.potentialReturnPct ?? 0
            heroCaption = "POTENTIAL RETURN"
            from = PeakFormat.usd(result.usd)
            to = PeakFormat.usd(result.toWinUSD)
            barKey = "POTENTIAL PROFIT"
            barValue = PeakReceiptFormat.signedUSD(result.potentialProfit ?? 0)
            cells = [
                PeakReceiptStat("ENTRY", PeakFormat.cents(result.price)),
                PeakReceiptStat("SIZE", PeakFormat.usd(result.usd)),
                PeakReceiptStat("TO WIN", PeakFormat.usd(result.toWinUSD), accent: true),
            ]
            chartKey = "\(label.uppercased()) · MARKET PRICE"
            chartText = PeakFormat.cents(result.price)
        }

        self.marketTitle = result.displayTitle
        self.outcomeLabel = label
        self.sideTag = "\(result.side.pastTitle.uppercased()) · \(outcome.uppercased())"
        self.status = isSell
            ? .closed(partial: result.isPartial)
            : .filled(partial: result.isPartial)
        self.heroValue = hero
        self.heroNumeric = heroRaw
        self.heroStyle = heroKind
        self.heroCaption = heroCaption
        self.heroFrom = from
        self.heroTo = to
        self.stats = cells
        self.footerKey = barKey
        self.footerValue = barValue
        self.priceHistory = nil
        self.entryIndex = 0
        self.chartLabel = chartKey
        self.chartValue = chartText
        self.impliedOdds = result.price
        self.handle = result.shareHandle ?? result.displayName
        self.timestamp = result.tradedAt
        self.referenceLabel = "SHARES"
        self.referenceValue = sharesText
        self.qrPayload = result.marketURL?.absoluteString
        self.isPositiveOutcome = positive
        self.isExit = isSell
        self.exitProfitable = profitable
    }

    /// Open or settled position → receipt.
    ///
    /// `priceHistory` is optional — pass a 0...1 series to swap the odds bar for
    /// the sparkline. Without it the card shows implied odds instead of a chart.
    init(position: PortfolioPosition, handle: String? = nil, priceHistory: [Double]? = nil) {
        let outcome = position.outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = outcome.lowercased()
        let label = outcome.isEmpty ? "Position" : outcome
        let positive = !(lowered == "no" || lowered == "n")
        let cost = position.size * position.avgPrice

        let state: Status
        if position.currentPrice >= 0.999 {
            state = .won
        } else if position.currentPrice <= 0.001 {
            state = .lost
        } else {
            state = .open
        }

        let hero: String
        var heroRaw: Double = 0
        let heroCaption: String
        let to: String
        let cells: [PeakReceiptStat]
        let barKey: String

        switch state {
        case .won:
            hero = PeakReceiptFormat.signedPercent(position.percentPnl)
            heroRaw = position.percentPnl
            heroCaption = "REALIZED RETURN"
            to = PeakFormat.usd(position.size)
            cells = [
                PeakReceiptStat("ENTRY", PeakFormat.cents(position.avgPrice)),
                PeakReceiptStat("EXIT", PeakFormat.cents(position.currentPrice)),
                PeakReceiptStat("PAYOUT", PeakFormat.usd(position.size), accent: true),
            ]
            barKey = "REALIZED P&L"
        case .lost:
            hero = PeakReceiptFormat.signedPercent(position.percentPnl)
            heroRaw = position.percentPnl
            heroCaption = "REALIZED RETURN"
            to = PeakFormat.usd(0)
            cells = [
                PeakReceiptStat("ENTRY", PeakFormat.cents(position.avgPrice)),
                PeakReceiptStat("EXIT", PeakFormat.cents(position.currentPrice)),
                PeakReceiptStat("PAYOUT", PeakFormat.usd(0), accent: true),
            ]
            barKey = "REALIZED P&L"
        default:
            let potential = cost > 0 ? ((position.size - cost) / cost) * 100 : 0
            hero = PeakReceiptFormat.signedPercent(potential)
            heroRaw = potential
            heroCaption = "POTENTIAL RETURN"
            to = PeakFormat.usd(position.size)
            cells = [
                PeakReceiptStat("ENTRY", PeakFormat.cents(position.avgPrice)),
                PeakReceiptStat("NOW", PeakFormat.cents(position.currentPrice)),
                PeakReceiptStat("TO WIN", PeakFormat.usd(position.size), accent: true),
            ]
            barKey = "UNREALIZED P&L"
        }

        self.marketTitle = position.title
        self.outcomeLabel = label
        self.sideTag = "HOLDING · \(outcome.uppercased())"
        self.status = state
        self.heroValue = hero
        self.heroNumeric = heroRaw
        self.heroStyle = .percent
        self.heroCaption = heroCaption
        self.heroFrom = PeakFormat.usd(cost)
        self.heroTo = to
        self.stats = cells
        self.footerKey = barKey
        self.footerValue = "\(PeakReceiptFormat.signedUSD(position.cashPnl))  (\(PeakReceiptFormat.signedPercent(position.percentPnl)))"
        self.priceHistory = priceHistory
        self.entryIndex = max(0, (priceHistory?.count ?? 1) / 3)
        self.chartLabel = "\(label.uppercased()) · NOW"
        self.chartValue = "\(PeakFormat.cents(position.currentPrice))  ·  ENTRY \(PeakFormat.cents(position.avgPrice))"
        self.impliedOdds = position.currentPrice
        self.handle = handle ?? "Peak trader"
        self.timestamp = Date()
        self.referenceLabel = "SHARES"
        self.referenceValue = TradeCelebrationResult.formatShares(position.size)
        self.qrPayload = position.eventSlug.map { "https://polymarket.com/event/\($0)" }
        self.isPositiveOutcome = positive
        self.isExit = false
        self.exitProfitable = nil
    }
}

// MARK: - Signed formatting

enum PeakReceiptFormat {
    /// `value` is already a percentage (87.7 → "+87.7%").
    static func signedPercent(_ value: Double) -> String {
        let sign = value < 0 ? "−" : "+"
        let magnitude = abs(value)
        let digits = magnitude >= 100 ? 0 : 1
        return sign + String(format: "%.\(digits)f%%", magnitude)
    }

    static func signedUSD(_ value: Double) -> String {
        (value < 0 ? "−" : "+") + PeakFormat.usd(abs(value))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Receipt · Filled buy") {
    PeakReceiptCard(data: PeakReceiptData(trade: .previewBuy))
        .padding(24)
        .background(Color.black)
}

#Preview("Receipt · Filled sell") {
    PeakReceiptCard(data: PeakReceiptData(trade: .previewSell))
        .padding(24)
        .background(Color.black)
}
#endif
