import SwiftUI
import UIKit

/// Trade / PnL accents — clearer on dark, still classy (not neon traffic lights).
enum PeakTradeStyle {
    static let buy = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.40, green: 0.78, blue: 0.58, alpha: 1)
        }
        return UIColor(red: 0.14, green: 0.50, blue: 0.38, alpha: 1)
    })

    static let sell = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.94, green: 0.48, blue: 0.50, alpha: 1)
        }
        return UIColor(red: 0.70, green: 0.28, blue: 0.32, alpha: 1)
    })

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
    static let importWalletRequired =
        "Import the private key or seed for this Polymarket wallet to enable trading."
    static let signFailed = "Couldn’t sign this order. Try again."
    static let insufficientFunds =
        "Not enough funds or allowance. Deposit under Portfolio, then try again."
    static let approvalsNeeded =
        "Trading approvals aren’t ready yet. Open Account → Set up trading, then try again."

    static func isImportWalletMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("import_wallet")
            || lower.contains("import the private key")
            || lower.contains("import your wallet")
            || lower == importWalletRequired.lowercased()
    }
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
            "typed_data", "unrecognized_keys", "invalid_data",
        ]
        if banned.contains(where: { lower.contains($0) }) {
            return fallback
        }
        // Never surface raw JSON error blobs.
        if text.hasPrefix("{"), text.contains("\"") {
            return fallback
        }
        return text
        #endif
    }

    /// Account status banner — always consumer-facing (even in DEBUG).
    static func accountStatus(_ text: String) -> String {
        let lower = text.lowercased()
        if isImportWalletMessage(text) {
            return importWalletRequired
        }
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
        return sanitizeOrderOrServerCopy(raw, fallback: fallback)
    }

    /// Map known order / signing failure shapes before generic sanitize.
    static func sanitizeOrderOrServerCopy(_ text: String, fallback: String) -> String {
        let lower = text.lowercased()
        if isImportWalletMessage(text) {
            return importWalletRequired
        }
        if lower.contains("typed_data")
            || lower.contains("unrecognized_keys")
            || lower.contains("invalid_data")
            || (lower.contains("params") && lower.contains("required"))
        {
            return signFailed
        }
        if lower.contains("allowance") || lower.contains("insufficient funds") || lower.contains("not enough balance") {
            return sanitize(text, fallback: insufficientFunds)
        }
        if lower.contains("approvals") {
            return approvalsNeeded
        }
        return sanitize(text, fallback: fallback)
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

/// Peak brand — sea-glass teal; slightly brighter mid on dark for chrome / CTAs.
enum PeakBrand {
    /// Ink teal for washes and depth.
    static let deep = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.12, green: 0.40, blue: 0.37, alpha: 1)
        }
        return UIColor(red: 0.06, green: 0.28, blue: 0.26, alpha: 1)
    })

    /// Primary brand / CTAs — aligned with AccentColor.
    static let mid = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.42, green: 0.82, blue: 0.72, alpha: 1)
        }
        return UIColor(red: 0.16, green: 0.55, blue: 0.48, alpha: 1)
    })

    static let soft = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.58, green: 0.88, blue: 0.80, alpha: 1)
        }
        return UIColor(red: 0.32, green: 0.62, blue: 0.56, alpha: 1)
    })

    static let mist = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.68, green: 0.88, blue: 0.82, alpha: 1)
        }
        return UIColor(red: 0.52, green: 0.70, blue: 0.66, alpha: 1)
    })
}

/// Canvas + elevated surfaces — flat, neutral, no tint washes.
/// Dark = pitch black. Light = clean paper white hierarchy.
enum PeakCanvas {
    /// Screen / list backdrop.
    static let background = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return .black
        }
        return UIColor(red: 0.965, green: 0.965, blue: 0.968, alpha: 1) // #F6F6F7
    })

    /// Grouped cards, list rows, panels.
    static let elevated = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1) // #121213
        }
        return .white
    })

    /// Nested controls / fields sitting on elevated.
    static let inset = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)
        }
        return UIColor(red: 0.945, green: 0.945, blue: 0.95, alpha: 1)
    })

    /// Hairline borders / separators.
    static let hairline = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1, alpha: 0.09)
        }
        return UIColor(white: 0, alpha: 0.08)
    })

    /// Soft brand rim for featured cards only (not backgrounds).
    static let brandRim = PeakBrand.mid.opacity(0.20)
}

/// Nav / tab chrome matched to Peak canvas (call from root on scheme change).
enum PeakChrome {
    static func apply(for scheme: ColorScheme) {
        let isDark = scheme == .dark
        let bg = isDark
            ? UIColor.black
            : UIColor(red: 0.965, green: 0.965, blue: 0.968, alpha: 1)
        let elevated = isDark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1)
            : UIColor.white

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bg
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.label]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(PeakBrand.mid)

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = bg
        tab.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = UIColor(PeakBrand.mid)

        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = elevated
    }
}

/// Flat Peak canvas only — never a wash or gradient behind app chrome.
struct PeakMaterialBackground: View {
    /// Kept for call-site compatibility; ignored (always flat).
    var intensity: CGFloat = 0
    var parallax: CGSize = .zero

    var body: some View {
        PeakCanvas.background
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
    var showGlow: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var radius: CGFloat {
        cornerRadius ?? size * 0.2237 // ~iOS app-icon squircle feel
    }

    var body: some View {
        let isLight = colorScheme == .light
        Image("PeakLogo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(isLight ? 0.08 : 0.40),
                radius: size * 0.08,
                y: size * 0.04
            )
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        ZStack {
            Circle()
                .fill(PeakCanvas.elevated)
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(isLight ? 0.06 : 0.35),
                    radius: isLight ? 8 : 14,
                    y: isLight ? 3 : 6
                )

            Image(systemName: kind.primarySymbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(PeakBrand.mid)
                .symbolRenderingMode(.hierarchical)

            Image(systemName: kind.secondarySymbol)
                .font(.system(size: size * 0.16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size * 0.34, height: size * 0.34)
                .background(Circle().fill(PeakBrand.mid))
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

/// Soft pulsing placeholder. Honors Reduce Motion (static, no shimmer).
struct PeakSkeleton: View {
    var height: CGFloat = 14
    var width: CGFloat? = nil
    var cornerRadius: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(PeakCanvas.inset)
            .frame(width: width, height: height)
            .opacity(reduceMotion ? 0.7 : (pulse ? 0.45 : 0.85))
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
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                PeakSkeleton(height: 16, width: nil, cornerRadius: 5)
                PeakSkeleton(height: 11, width: 160, cornerRadius: 4)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                PeakSkeleton(height: 20, width: 44, cornerRadius: 5)
                PeakSkeleton(height: 8, width: 28, cornerRadius: 3)
            }
        }
        .padding(.vertical, 10)
    }
}

/// Portfolio summary placeholder (hero cash + metrics + CTA).
struct PeakSkeletonSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PeakSkeleton(height: 12, width: 48, cornerRadius: 4)
            PeakSkeleton(height: 40, width: 180, cornerRadius: 10)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    PeakSkeleton(height: 8, width: 52, cornerRadius: 3)
                    PeakSkeleton(height: 16, width: 72, cornerRadius: 5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    PeakSkeleton(height: 8, width: 28, cornerRadius: 3)
                    PeakSkeleton(height: 16, width: 64, cornerRadius: 5)
                }
                Spacer()
            }
            PeakSkeleton(height: 50, width: nil, cornerRadius: PeakLayout.ctaRadius)
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

/// Continuous radii, gutters, and touch targets — tight, intentional, not bubbly.
enum PeakLayout {
    /// Primary filled CTAs / Buy·Sell.
    static let ctaRadius: CGFloat = 12
    /// Grouped content panels / hero cards.
    static let cardRadius: CGFloat = 14
    /// Compact chips, pickers, fields.
    static let controlRadius: CGFloat = 10
    /// Badge / metric capsules.
    static let badgeRadius: CGFloat = 8
    /// Screen / list horizontal inset.
    static let gutter: CGFloat = 16
    /// Stack spacing inside cards.
    static let stack: CGFloat = 12
    /// Row vertical rhythm.
    static let rowPadding: CGFloat = 10
    /// Minimum interactive height (HIG).
    static let minTap: CGFloat = 44
    /// WhatsApp-style page headline top padding under the toolbar.
    static let pageHeaderTop: CGFloat = 6
    /// Space under the page headline before content.
    static let pageHeaderBottom: CGFloat = 10

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    }

    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
    }

    static var ctaShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ctaRadius, style: .continuous)
    }
}

/// Large tab headline — WhatsApp / liquid iOS placement (title lives in content, not the nav bar).
struct PeakPageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .default))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, PeakLayout.pageHeaderTop)
        .padding(.bottom, PeakLayout.pageHeaderBottom)
        .accessibilityElement(children: .combine)
    }
}

/// Circular toolbar control — matches liquid dark chrome (WhatsApp-style).
struct PeakToolbarCircle: View {
    let systemImage: String
    var emphasized: Bool = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(emphasized ? Color.white : Color.primary)
            .frame(width: 34, height: 34)
            .background {
                Circle()
                    .fill(emphasized ? PeakBrand.mid : PeakCanvas.inset)
            }
            .overlay {
                if !emphasized {
                    Circle().strokeBorder(PeakCanvas.hairline, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// Root tab: actions stay in the bar; large headline is `PeakPageHeader` in content.
    /// Keeps `navigationTitle` for the back-button label when pushing detail.
    func peakRootTab(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Hide the inline center title — headline lives in the page body.
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .peakChrome()
    }

    /// First list row: page headline with WhatsApp-style placement.
    func peakPageHeaderRow() -> some View {
        self
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: PeakLayout.gutter,
                bottom: 0,
                trailing: PeakLayout.gutter
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension View {
    /// Content panels on Peak elevated surface with a hairline rim.
    func peakContentCard() -> some View {
        self
            .padding(PeakLayout.stack + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PeakCanvas.elevated, in: PeakLayout.cardShape)
            .overlay {
                PeakLayout.cardShape.strokeBorder(PeakCanvas.hairline, lineWidth: 1)
            }
    }

    /// Screen backdrop + scroll canvas.
    func peakScreenBackground() -> some View {
        self.background(PeakMaterialBackground())
    }

    /// Inset grouped list on Peak canvas (call after List content).
    func peakListStyle() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(PeakCanvas.hairline)
    }

    /// Elevated list row fill for inset grouped sections.
    func peakListRow() -> some View {
        self.listRowBackground(PeakCanvas.elevated)
    }

    /// Floating controls only — Liquid Glass on iOS 26+ when transparency is allowed.
    @ViewBuilder
    func peakFloatingChrome() -> some View {
        modifier(PeakFloatingChromeModifier())
    }

    func peakChrome() -> some View {
        self
            .toolbarBackground(PeakCanvas.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// Sheets: pitch Peak canvas; glass stays on system chrome.
    func peakSheetChrome() -> some View {
        self
            .presentationDragIndicator(.visible)
            .presentationBackground(PeakCanvas.background)
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
            in: PeakLayout.ctaShape
        )
        .overlay {
            PeakLayout.ctaShape.strokeBorder(
                Color.white.opacity(0.10),
                lineWidth: 1
            )
        }
        .contentShape(PeakLayout.ctaShape)
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
            content.background(PeakCanvas.inset, in: Capsule())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
