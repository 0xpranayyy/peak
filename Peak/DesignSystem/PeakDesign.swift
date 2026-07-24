import SwiftUI

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

struct PeakMaterialBackground: View {
    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }
}

extension View {
    /// Content sections sit on solid/grouped surfaces — not Liquid Glass (HIG: glass is for chrome).
    func peakContentCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
