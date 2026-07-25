import Foundation
import UIKit
import UserNotifications

struct PriceAlert: Identifiable, Hashable, Codable, Sendable {
    enum Direction: String, Codable, Sendable, CaseIterable {
        case atOrAbove
        case atOrBelow

        var title: String {
            switch self {
            case .atOrAbove: return "Hits or rises to"
            case .atOrBelow: return "Drops to or below"
            }
        }
    }

    let id: String
    let eventID: String
    let eventTitle: String
    let marketID: String
    let tokenID: String
    let outcomeLabel: String
    let targetPrice: Double
    let direction: Direction
    var isActive: Bool
    var triggeredAt: Date?
    let createdAt: Date

    var targetCentsLabel: String {
        PeakFormat.cents(targetPrice)
    }

    func isTriggered(by price: Double) -> Bool {
        switch direction {
        case .atOrAbove: return price >= targetPrice
        case .atOrBelow: return price <= targetPrice
        }
    }
}

@MainActor
final class PriceAlertStore: ObservableObject {
    static let shared = PriceAlertStore()

    private let storageKey = "peak.priceAlerts.v1"

    @Published private(set) var alerts: [PriceAlert] = []

    init() {
        load()
    }

    var activeAlerts: [PriceAlert] {
        alerts.filter { $0.isActive && $0.triggeredAt == nil }
    }

    func alerts(forEventID eventID: String) -> [PriceAlert] {
        alerts.filter { $0.eventID == eventID }
    }

    func add(
        event: PeakEvent,
        market: Market,
        isYes: Bool,
        targetPrice: Double,
        direction: PriceAlert.Direction
    ) -> PriceAlert? {
        let token = isYes ? market.yesTokenID : market.noTokenID
        guard let token, !token.isEmpty else { return nil }
        let clamped = min(0.99, max(0.01, (targetPrice * 100).rounded() / 100))
        let alert = PriceAlert(
            id: UUID().uuidString,
            eventID: event.id,
            eventTitle: event.title,
            marketID: market.id,
            tokenID: token,
            outcomeLabel: isYes ? market.yesLabel : market.noLabel,
            targetPrice: clamped,
            direction: direction,
            isActive: true,
            triggeredAt: nil,
            createdAt: Date()
        )
        alerts.insert(alert, at: 0)
        persist()
        return alert
    }

    func remove(id: String) {
        alerts.removeAll { $0.id == id }
        persist()
    }

    func clearTriggered() {
        alerts.removeAll { $0.triggeredAt != nil }
        persist()
    }

    func markTriggered(_ id: String) {
        guard let idx = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[idx].triggeredAt = Date()
        alerts[idx].isActive = false
        persist()
    }

    /// Evaluate live/polled price; returns newly triggered alerts.
    func evaluate(tokenID: String, price: Double) -> [PriceAlert] {
        guard price > 0, price < 1 else { return [] }
        var fired: [PriceAlert] = []
        for alert in activeAlerts where alert.tokenID == tokenID {
            if alert.isTriggered(by: price) {
                markTriggered(alert.id)
                if let updated = alerts.first(where: { $0.id == alert.id }) {
                    fired.append(updated)
                }
            }
        }
        return fired
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data) else {
            alerts = []
            return
        }
        alerts = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        objectWillChange.send()
    }
}

@MainActor
final class PriceAlertMonitor: ObservableObject {
    static let shared = PriceAlertMonitor()

    @Published private(set) var notificationsAllowed = false

    private var pollTask: Task<Void, Never>?

    func start() {
        Task { await refreshAuthorizationStatus() }
        restartPolling()
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkOnce()
                self?.restartPolling()
            }
        }
    }

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsAllowed = granted
            return granted
        } catch {
            notificationsAllowed = false
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    func handleLivePrice(tokenID: String, price: Double) {
        let fired = PriceAlertStore.shared.evaluate(tokenID: tokenID, price: price)
        for alert in fired {
            notify(alert: alert, price: price)
        }
    }

    func checkOnce() async {
        let active = PriceAlertStore.shared.activeAlerts
        guard !active.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for alert in active {
                group.addTask {
                    do {
                        guard let price = try await CLOBAPI.fetchPrice(tokenID: alert.tokenID, side: "buy") else {
                            return
                        }
                        await MainActor.run {
                            self.handleLivePrice(tokenID: alert.tokenID, price: price)
                        }
                    } catch {
                        // Ignore individual poll failures.
                    }
                }
            }
        }
    }

    private func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkOnce()
                try? await Task.sleep(nanoseconds: 45_000_000_000) // 45s
            }
        }
    }

    private func notify(alert: PriceAlert, price: Double) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let content = UNMutableNotificationContent()
        content.title = "\(alert.outcomeLabel) \(PeakFormat.cents(price))"
        content.body = "\(alert.eventTitle): target \(alert.targetCentsLabel) hit."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "peak.alert.\(alert.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
