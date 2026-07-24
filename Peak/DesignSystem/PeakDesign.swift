import SwiftUI

enum PeakFormat {
    static func cents(_ probability: Double) -> String {
        let cents = (probability * 100).rounded()
        return "\(Int(cents))¢"
    }

    static func percent(_ probability: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", probability * 100)
    }

    static func usd(_ value: Double, compact: Bool = false) -> String {
        if compact {
            return compactCurrency(value)
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value >= 100 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }

    static func compactCurrency(_ value: Double) -> String {
        let absValue = Swift.abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...:
            return "\(sign)$(String(format: "%.1f", absValue / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)$(String(format: "%.1f", absValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)$(String(format: "%.1f", absValue / 1_000))K"
        default:
            return "\(sign)$\(String(format: "%.0f", absValue))"
        }
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
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
        Group {
            if #available(iOS 26.0, *) {
                // Liquid Glass-friendly system background; glass materials applied on chrome.
                Color.clear
                    .background(.background)
            } else {
                Color(.systemGroupedBackground)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder
    func peakGlassCard() -> some View {
        if #available(iOS 26.0, *) {
            self
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    func peakChrome() -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackground(.visible, for: .navigationBar, .tabBar)
        } else {
            self
        }
    }
}
