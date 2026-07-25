import Foundation
import UserNotifications

@MainActor
final class DailyDigestStore: ObservableObject {
    static let shared = DailyDigestStore()

    private let enabledKey = "peak.digest.enabled"
    private let hourKey = "peak.digest.hour"
    private let lastKey = "peak.digest.lastDeliveredDay"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            Task { await reschedule() }
        }
    }

    @Published var hour: Int {
        didSet {
            UserDefaults.standard.set(hour, forKey: hourKey)
            Task { await reschedule() }
        }
    }

    @Published private(set) var movers: [PeakEvent] = []
    @Published private(set) var isLoading = false
    @Published var showBanner = false

    init() {
        isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        hour = UserDefaults.standard.object(forKey: hourKey) as? Int ?? 9
    }

    func refreshMovers(interests: [MarketCategory]) async {
        isLoading = true
        defer { isLoading = false }

        var collected: [PeakEvent] = []
        // Cap categories AND avoid alternate-slug storms — Markets list owns the host budget.
        let categories = Array((interests.isEmpty ? Array(MarketCategory.allCases.prefix(3)) : interests).prefix(3))

        await withTaskGroup(of: [PeakEvent].self) { group in
            for category in categories {
                group.addTask {
                    // Primary slug only — alternate retries are for explicit category taps.
                    (try? await GammaAPI.fetchEvents(
                        limit: 8,
                        offset: 0,
                        sort: .trending,
                        tagSlug: category.slug
                    )) ?? []
                }
            }
            for await page in group {
                collected.append(contentsOf: page)
            }
        }

        var seen = Set<String>()
        movers = MarketShowcase.rankTrending(
            collected.filter { seen.insert($0.id).inserted }
        )
        .prefix(6)
        .map { $0 }

        maybeRevealBanner()
        await reschedule()
    }

    func dismissBanner() {
        showBanner = false
        markDeliveredToday()
    }

    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["peak.daily.digest"])

        guard isEnabled else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your Peak digest"
        if let top = movers.first {
            content.body = "\(top.title) is moving at \(PeakFormat.cents(top.displayProbability ?? 0.5)) Yes. Open Peak for today’s top markets."
        } else {
            content.body = "Top markets in your categories are ready. Open Peak to catch up."
        }
        content.sound = .default

        var date = DateComponents()
        date.hour = hour
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: "peak.daily.digest", content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func maybeRevealBanner() {
        let day = Self.dayStamp(Date())
        let last = UserDefaults.standard.string(forKey: lastKey)
        let hourNow = Calendar.current.component(.hour, from: Date())
        if isEnabled, !movers.isEmpty, last != day, hourNow >= hour {
            showBanner = true
        }
    }

    private func markDeliveredToday() {
        UserDefaults.standard.set(Self.dayStamp(Date()), forKey: lastKey)
    }

    private static func dayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
