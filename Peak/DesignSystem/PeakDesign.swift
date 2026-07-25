import SwiftUI
import UIKit

/// Trade action colors — buy green / sell red across Peak.
enum PeakTradeStyle {
    static let buy = Color(red: 0.11, green: 0.68, blue: 0.42)
    static let sell = Color(red: 0.90, green: 0.27, blue: 0.33)

    /// Polymarket display rule: midpoint unless spread > 10¢, then last trade.
    static func displayedOdds(mid: Double?, spread: Double?, lastTrade: Double?, fallback: Double) -> Double {
        if let spread, spread > 0.10, let lastTrade, lastTrade >= 0, lastTrade <= 1 {
            return lastTrade
        }
        if let mid, mid > 0, mid < 1 { return mid }
        if let lastTrade, lastTrade >= 0, lastTrade <= 1 { return lastTrade }
        return fallback
    }
}

/// Calm, non-infra strings for Release UI. DEBUG keeps raw detail.
enum PeakUserCopy {
    static let missingPolymarketAccount =
        "We couldn’t find an account for this wallet. Under More options, import your wallet or paste your profile address."
    static let offline = "You’re offline. Check your connection and try again."
    static let timedOut = "That took too long. Try again."
    static let couldNotConnect = "Couldn’t connect. Try again."

    static func sanitize(_ text: String, fallback: String = "Something went wrong. Try again.") -> String {
        #if DEBUG
        return text
        #else
        let lower = text.lowercased()
        let banned = [
            "backend", "proxy", "builder", "relayer", "app_token", "peak_backend",
            "clob", "funder", "127.0.0.1", "localhost", "privy dashboard",
            "app client", "allowed app", "bundle id", "walletconnect",
            "privysecrets", "decode response", "invalid url", "server returned",
            "empty response", "http ", "signer", "gnosis", "safe address",
        ]
        if banned.contains(where: { lower.contains($0) }) {
            return fallback
        }
        return text
        #endif
    }

    /// Account status banner — always consumer-facing (even in DEBUG).
    static func accountStatus(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("no polymarket account") || lower.contains("for this signer") {
            return missingPolymarketAccount
        }
        if lower.contains("ready") || lower.contains("synced") || lower.contains("configured") {
            return "You’re set up to trade."
        }
        if lower.contains("deploy") || lower.contains("pending") || lower.contains("progress") {
            return "Setup still finishing. Try again in a moment."
        }
        return sanitize(text, fallback: "Setup still finishing. Try again in a moment.")
    }

    static func fromError(_ error: Error, fallback: String = "Something went wrong. Try again.") -> String {
        if let mapped = networkMessage(for: error) {
            return mapped
        }
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return sanitize(raw, fallback: fallback)
    }

    /// Map transport failures to calm offline / timeout copy.
    static func networkMessage(for error: Error) -> String? {
        let code: URLError.Code?
        if let urlError = error as? URLError {
            code = urlError.code
        } else {
            let ns = error as NSError
            guard ns.domain == NSURLErrorDomain else { return nil }
            code = URLError.Code(rawValue: ns.code)
        }
        guard let code else { return nil }
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return offline
        case .timedOut:
            return timedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return couldNotConnect
        default:
            return nil
        }
    }
}

enum PeakFormat {
    static func cents(_ probability: Double) -> String {
        let cents = (probability * 100).rounded()
        return "\(Int(cents))¢"
    }

    static func percent(_ probability: Double, digits: Int = 1) -> String {
        let format = "%.\(digits)f%%"
        return String(format: format, probability * 100)
    }

    static func usd(_ value: Double, compact: Bool = false) -> String {
        if compact {
            return compactCurrency(value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value >= 100 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    static func compactCurrency(_ value: Double) -> String {
        let absValue = Swift.abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...:
            let amount = String(format: "%.1f", absValue / 1_000_000_000)
            return "\(sign)$\(amount)B"
        case 1_000_000...:
            let amount = String(format: "%.1f", absValue / 1_000_000)
            return "\(sign)$\(amount)M"
        case 1_000...:
            let amount = String(format: "%.1f", absValue / 1_000)
            return "\(sign)$\(amount)K"
        default:
            let amount = String(format: "%.0f", absValue)
            return "\(sign)$\(amount)"
        }
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func relativeEnd(_ date: Date?) -> String {
        guard let date else { return "Open" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Peak brand teal — adaptive Light / Dark (matches AccentColor family).
enum PeakBrand {
    /// Deepest teal — richer on Light so washes don't muddy white canvases.
    static let deep = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.14, green: 0.46, blue: 0.42, alpha: 1)
        }
        return UIColor(red: 0.08, green: 0.36, blue: 0.32, alpha: 1)
    })

    /// Primary brand — aligned with AccentColor (brighter in Dark).
    static let mid = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.32, green: 0.82, blue: 0.62, alpha: 1)
        }
        return UIColor(red: 0.18, green: 0.655, blue: 0.502, alpha: 1)
    })

    static let soft = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.42, green: 0.86, blue: 0.74, alpha: 1)
        }
        return UIColor(red: 0.28, green: 0.70, blue: 0.60, alpha: 1)
    })

    static let mist = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.55, green: 0.80, blue: 0.74, alpha: 1)
        }
        return UIColor(red: 0.48, green: 0.74, blue: 0.68, alpha: 1)
    })
}

/// Soft atmospheric mesh used behind Markets / Portfolio / onboarding.
struct PeakMaterialBackground: View {
    /// Stronger presence for brand-first surfaces (onboarding hero).
    var intensity: CGFloat = 1
    /// Subtle mesh drift for page parallax (points). Honored by callers that respect Reduce Motion.
    var parallax: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        ZStack {
            Color(.systemGroupedBackground)

            // Top-leading wash — Peak teal into clear (tuned per mode).
            LinearGradient(
                colors: [
                    PeakBrand.deep.opacity((isLight ? 0.07 : 0.12) * intensity),
                    PeakBrand.mid.opacity((isLight ? 0.055 : 0.06) * intensity),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .offset(x: parallax.width * 0.35, y: parallax.height * 0.35)

            // Soft radial mesh blobs — atmosphere, not neon.
            PeakAtmosphereMesh(intensity: intensity, parallax: parallax)
        }
        .ignoresSafeArea()
    }
}

/// Reusable brand gradient mesh (SwiftUI ellipses — no image assets).
struct PeakAtmosphereMesh: View {
    var intensity: CGFloat = 1
    var parallax: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                PeakBrand.mid.opacity((isLight ? 0.10 : 0.16) * intensity),
                                PeakBrand.mid.opacity(0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(w, h) * 0.55
                        )
                    )
                    .frame(width: w * 1.1, height: h * 0.7)
                    .position(x: w * 0.15 + parallax.width, y: h * 0.08 + parallax.height * 0.6)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                PeakBrand.soft.opacity((isLight ? 0.08 : 0.11) * intensity),
                                PeakBrand.soft.opacity(0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(w, h) * 0.45
                        )
                    )
                    .frame(width: w * 0.9, height: h * 0.55)
                    .position(x: w * 0.92 - parallax.width * 0.7, y: h * 0.28 + parallax.height * 0.4)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                PeakBrand.deep.opacity((isLight ? 0.05 : 0.09) * intensity),
                                PeakBrand.deep.opacity(0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(w, h) * 0.5
                        )
                    )
                    .frame(width: w * 0.85, height: h * 0.5)
                    .position(x: w * 0.45 + parallax.width * 0.35, y: h * 0.92 - parallax.height * 0.5)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// App icon / brand logo for onboarding and marketing surfaces.
struct PeakAppLogo: View {
    var size: CGFloat = 96
    var cornerRadius: CGFloat? = nil
    var showGlow: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var radius: CGFloat {
        cornerRadius ?? size * 0.2237 // ~iOS app-icon squircle feel
    }

    var body: some View {
        let isLight = colorScheme == .light
        ZStack {
            if showGlow {
                RoundedRectangle(cornerRadius: radius * 1.08, style: .continuous)
                    .fill(PeakBrand.mid.opacity(isLight ? 0.16 : 0.28))
                    .frame(width: size * 1.18, height: size * 1.18)
                    .blur(radius: size * 0.12)
            }

            Image("PeakLogo")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(isLight ? 0.06 : 0.14),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: PeakBrand.deep.opacity(isLight ? 0.18 : 0.35),
                    radius: size * 0.14,
                    y: size * 0.08
                )
        }
        .accessibilityLabel("Peak")
    }
}

/// Geometric Peak mark — ascending peak / chevron, brand teal.
struct PeakMark: View {
    var size: CGFloat = 56
    var filled: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        ZStack {
            if filled {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                PeakBrand.mid.opacity(isLight ? 0.14 : 0.24),
                                PeakBrand.deep.opacity(isLight ? 0.06 : 0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 1.55, height: size * 1.55)

                Circle()
                    .strokeBorder(PeakBrand.mid.opacity(isLight ? 0.22 : 0.20), lineWidth: 1)
                    .frame(width: size * 1.55, height: size * 1.55)
            }

            PeakMarkShape()
                .fill(
                    LinearGradient(
                        colors: [PeakBrand.soft, PeakBrand.mid, PeakBrand.deep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size * 0.78)
                .shadow(
                    color: PeakBrand.deep.opacity(isLight ? 0.14 : 0.22),
                    radius: size * 0.12,
                    y: size * 0.06
                )
        }
        .accessibilityHidden(true)
    }
}

/// Simple mountain / peak glyph.
struct PeakMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // Left foothill
        path.move(to: CGPoint(x: 0, y: h * 0.92))
        path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.62))
        // Main peak
        path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.08))
        path.addLine(to: CGPoint(x: w, y: h * 0.92))
        path.closeSubpath()
        return path
    }
}

/// Illustration-like empty-state icon stack (SF Symbols + soft brand discs).
enum PeakEmptyKind {
    case markets
    case watchlist
    case portfolio
    case search
    case chart

    var primarySymbol: String {
        switch self {
        case .markets: return "chart.bar.doc.horizontal"
        case .watchlist: return "star"
        case .portfolio: return "wallet.pass"
        case .search: return "magnifyingglass"
        case .chart: return "chart.xyaxis.line"
        }
    }

    var secondarySymbol: String {
        switch self {
        case .markets: return "arrow.up.right"
        case .watchlist: return "bookmark"
        case .portfolio: return "coloncurrencysign"
        case .search: return "text.magnifyingglass"
        case .chart: return "waveform.path"
        }
    }
}

struct PeakEmptyVisual: View {
    let kind: PeakEmptyKind
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            PeakBrand.mid.opacity(0.16),
                            PeakBrand.mid.opacity(0.04),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.72
                    )
                )
                .frame(width: size * 1.45, height: size * 1.45)

            Circle()
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .strokeBorder(PeakBrand.mid.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: PeakBrand.deep.opacity(0.08), radius: 12, y: 4)

            Image(systemName: kind.primarySymbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [PeakBrand.soft, PeakBrand.mid],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)

            // Satellite accent chip
            Image(systemName: kind.secondarySymbol)
                .font(.system(size: size * 0.16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size * 0.34, height: size * 0.34)
                .background(
                    Circle().fill(PeakBrand.mid)
                )
                .offset(x: size * 0.34, y: size * 0.30)
        }
        .frame(width: size * 1.45, height: size * 1.45)
        .accessibilityHidden(true)
    }
}

/// Ghost sparkline for bare chart empty states.
struct PeakChartPlaceholder: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.move(to: CGPoint(x: 0, y: h * 0.62))
                path.addCurve(
                    to: CGPoint(x: w * 0.28, y: h * 0.48),
                    control1: CGPoint(x: w * 0.1, y: h * 0.7),
                    control2: CGPoint(x: w * 0.18, y: h * 0.38)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.55, y: h * 0.58),
                    control1: CGPoint(x: w * 0.38, y: h * 0.58),
                    control2: CGPoint(x: w * 0.45, y: h * 0.72)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.82, y: h * 0.32),
                    control1: CGPoint(x: w * 0.65, y: h * 0.42),
                    control2: CGPoint(x: w * 0.72, y: h * 0.28)
                )
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.4),
                    control1: CGPoint(x: w * 0.9, y: h * 0.35),
                    control2: CGPoint(x: w * 0.95, y: h * 0.42)
                )
            }
            .stroke(
                PeakBrand.mid.opacity(0.35),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 6])
            )

            Path { path in
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h * 0.62))
                path.addCurve(
                    to: CGPoint(x: w * 0.28, y: h * 0.48),
                    control1: CGPoint(x: w * 0.1, y: h * 0.7),
                    control2: CGPoint(x: w * 0.18, y: h * 0.38)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.55, y: h * 0.58),
                    control1: CGPoint(x: w * 0.38, y: h * 0.58),
                    control2: CGPoint(x: w * 0.45, y: h * 0.72)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.82, y: h * 0.32),
                    control1: CGPoint(x: w * 0.65, y: h * 0.42),
                    control2: CGPoint(x: w * 0.72, y: h * 0.28)
                )
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.4),
                    control1: CGPoint(x: w * 0.9, y: h * 0.35),
                    control2: CGPoint(x: w * 0.95, y: h * 0.42)
                )
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [PeakBrand.mid.opacity(0.12), PeakBrand.mid.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Soft pulsing placeholder — Peak teal wash. Honors Reduce Motion (static, no shimmer).
struct PeakSkeleton: View {
    var height: CGFloat = 14
    var width: CGFloat? = nil
    var cornerRadius: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulse = false

    var body: some View {
        let isLight = colorScheme == .light
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        PeakBrand.mid.opacity(isLight ? 0.14 : 0.22),
                        PeakBrand.deep.opacity(isLight ? 0.07 : 0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: height)
            .opacity(reduceMotion ? 0.55 : (pulse ? 0.42 : 0.78))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// One market-style row placeholder.
struct PeakSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                PeakSkeleton(height: 10, width: 64, cornerRadius: 4)
                PeakSkeleton(height: 16, width: nil, cornerRadius: 6)
                PeakSkeleton(height: 12, width: 140, cornerRadius: 5)
            }
            Spacer(minLength: 8)
            PeakSkeleton(height: 28, width: 48, cornerRadius: 10)
        }
        .padding(.vertical, 6)
    }
}

/// Portfolio summary placeholder (value + cash / PnL chips).
struct PeakSkeletonSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PeakSkeleton(height: 10, width: 72, cornerRadius: 4)
            PeakSkeleton(height: 34, width: 160, cornerRadius: 8)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    PeakSkeleton(height: 8, width: 36, cornerRadius: 3)
                    PeakSkeleton(height: 18, width: 72, cornerRadius: 5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    PeakSkeleton(height: 8, width: 28, cornerRadius: 3)
                    PeakSkeleton(height: 18, width: 64, cornerRadius: 5)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

/// Drop-in list of skeleton rows for Markets / Portfolio initial load.
struct PeakSkeletonList: View {
    var style: Style = .markets
    var rowCount: Int = 8

    enum Style {
        case markets
        case portfolio
    }

    var body: some View {
        List {
            switch style {
            case .markets:
                Section {
                    ForEach(0..<rowCount, id: \.self) { _ in
                        PeakSkeletonRow()
                    }
                }
            case .portfolio:
                Section {
                    PeakSkeletonSummary()
                }
                Section {
                    ForEach(0..<max(3, rowCount / 2), id: \.self) { _ in
                        PeakSkeletonRow()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading")
    }
}

/// Shared springs — presence and hierarchy, not decoration.
enum PeakMotion {
    static let appear = Animation.spring(response: 0.48, dampingFraction: 0.86)
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let soft = Animation.spring(response: 0.40, dampingFraction: 0.88)
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Stagger delay for list rows — capped so deep indices stay cheap.
    static func staggerDelay(index: Int, step: Double = 0.04, cap: Int = 5) -> Double {
        Double(min(max(index, 0), cap)) * step
    }

    /// Only animate the first screenful of list rows (avoids recycle jank).
    static let appearRowCap = 6
}

/// Continuous corner radii + touch targets aligned with iOS 26 HIG (not pill spam).
enum PeakLayout {
    /// Primary filled CTAs / Buy·Sell trade actions (~14–16 continuous).
    static let ctaRadius: CGFloat = 14
    /// Grouped content panels (solid surface — not Liquid Glass).
    static let cardRadius: CGFloat = 16
    /// Compact chips, market pickers, text fields.
    static let controlRadius: CGFloat = 12
    /// Minimum interactive height (HIG).
    static let minTap: CGFloat = 44
}

extension View {
    /// Content sections sit on solid/grouped surfaces — not Liquid Glass (HIG: glass is for chrome).
    func peakContentCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: PeakLayout.cardRadius, style: .continuous)
            )
    }

    /// Floating controls only — Liquid Glass on iOS 26+ when transparency is allowed.
    @ViewBuilder
    func peakFloatingChrome() -> some View {
        modifier(PeakFloatingChromeModifier())
    }

    @ViewBuilder
    func peakChrome() -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackground(.automatic, for: .navigationBar, .tabBar)
        } else {
            self
        }
    }

    /// Sheets: solid grouped canvas for Form/List density; glass stays on system chrome.
    func peakSheetChrome() -> some View {
        self
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(.systemGroupedBackground))
    }

    /// Soft fade + rise on first appear. Honors Reduce Motion.
    func peakAppear(delay: Double = 0) -> some View {
        modifier(PeakAppearModifier(delay: delay))
    }

    /// Numeric text cross-fade when odds / prices tick.
    func peakNumeric(value: some Equatable) -> some View {
        self
            .contentTransition(.numericText())
            .animation(PeakMotion.snappy, value: value)
    }

    /// Soft insert/remove for status / blocked panels.
    func peakStatusTransition() -> some View {
        self.transition(
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .offset(y: -4)),
                removal: .opacity.combined(with: .scale(scale: 0.98))
            )
        )
    }

    /// Press scale + light haptic. Use instead of stacking another `buttonStyle`.
    func peakPressable(haptic: Bool = true) -> some View {
        buttonStyle(PeakPressableButtonStyle(haptic: haptic))
    }
}

/// Primary full-width CTA — continuous iOS 26 radius, brand/accent or PeakTradeStyle tint.
/// Prefer system `.borderedProminent` for simple accent actions; keep this for buy/sell coding.
struct PeakPrimaryCTA: View {
    let title: String
    var systemImage: String? = nil
    var color: Color = .accentColor
    var isLoading: Bool = false
    var isEnabled: Bool = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(minHeight: 50)
        .background(
            (isEnabled ? color : color.opacity(0.45)),
            in: RoundedRectangle(cornerRadius: PeakLayout.ctaRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: PeakLayout.ctaRadius, style: .continuous))
        .accessibilityAddTraits(.isButton)
    }
}

/// Scale / opacity press — for custom chrome CTAs (trade, onboarding, setup).
struct PeakPressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.975
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        PeakPressableButtonBody(
            configuration: configuration,
            scale: scale,
            haptic: haptic
        )
    }
}

private struct PeakPressableButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var scale: CGFloat
    var haptic: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(reduceMotion ? nil : PeakMotion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, haptic { PeakHaptics.press() }
            }
    }
}

extension ButtonStyle where Self == PeakPressableButtonStyle {
    static var peakPressable: PeakPressableButtonStyle { PeakPressableButtonStyle() }

    static func peakPressable(haptic: Bool) -> PeakPressableButtonStyle {
        PeakPressableButtonStyle(haptic: haptic)
    }
}

private struct PeakAppearModifier: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible || reduceMotion ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 8)
            .onAppear {
                guard !visible else { return }
                if reduceMotion {
                    visible = true
                    return
                }
                withAnimation(PeakMotion.appear.delay(delay)) {
                    visible = true
                }
            }
    }
}

private struct PeakFloatingChromeModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(.secondarySystemGroupedBackground), in: Capsule())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
