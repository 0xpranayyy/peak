import UIKit

enum PeakHaptics {
    @MainActor
    private static var lastTickAt: [String: (price: Double, date: Date)] = [:]

    /// Soft tick when odds jump by >= threshold (default 1¢).
    @MainActor
    static func oddsMove(tokenID: String, price: Double, threshold: Double = 0.01) {
        guard price > 0, price < 1 else { return }
        let now = Date()
        if let last = lastTickAt[tokenID] {
            let dt = now.timeIntervalSince(last.date)
            let dp = abs(price - last.price)
            lastTickAt[tokenID] = (price, now)
            guard dt > 0.35, dp >= threshold else { return }
            let style: UIImpactFeedbackGenerator.FeedbackStyle = dp >= 0.03 ? .medium : .light
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        } else {
            lastTickAt[tokenID] = (price, now)
        }
    }

    /// Light press for primary CTAs / trade buttons.
    @MainActor
    static func press() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65)
    }

    @MainActor
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Soft confirmation when pull-to-refresh completes a user-initiated reload.
    @MainActor
    static func refresh() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
    }
}
