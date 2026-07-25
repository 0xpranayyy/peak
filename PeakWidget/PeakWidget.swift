import WidgetKit
import SwiftUI

@main
struct PeakWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrendingMarketWidget()
    }
}

struct TrendingEntry: TimelineEntry {
    let date: Date
    let question: String
    let cents: Int
    let volume: String
}

struct TrendingProvider: TimelineProvider {
    private static let fallback = TrendingEntry(
        date: .now,
        question: "Will Bitcoin hit a new ATH this month?",
        cents: 42,
        volume: "$1.2M"
    )

    func placeholder(in context: Context) -> TrendingEntry { Self.fallback }

    func getSnapshot(in context: Context, completion: @escaping (TrendingEntry) -> Void) {
        completion(Self.fallback)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendingEntry>) -> Void) {
        Task {
            let entry = (try? await fetchTrending()) ?? Self.fallback
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }

    private func fetchTrending() async throws -> TrendingEntry {
        var comps = URLComponents(string: "https://gamma-api.polymarket.com/markets")!
        comps.queryItems = [
            .init(name: "limit", value: "1"),
            .init(name: "active", value: "true"),
            .init(name: "closed", value: "false"),
            .init(name: "archived", value: "false"),
            .init(name: "order", value: "volume24hr"),
            .init(name: "ascending", value: "false"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let market = rows.first,
              let question = market["question"] as? String else {
            return Self.fallback
        }

        var yes = 0.5
        if let pricesJSON = (market["outcomePrices"] as? String)?.data(using: .utf8),
           let prices = try? JSONDecoder().decode([String].self, from: pricesJSON),
           let first = prices.first,
           let parsed = Double(first) {
            yes = parsed
        } else if let prices = market["outcomePrices"] as? [Any],
                  let first = prices.first {
            if let d = first as? Double { yes = d }
            else if let s = first as? String, let d = Double(s) { yes = d }
        }

        let volume = (market["volume24hr"] as? Double)
            ?? (market["volumeNum"] as? Double)
            ?? 0
        let volumeText: String
        switch volume {
        case 1_000_000...: volumeText = String(format: "$%.1fM", volume / 1_000_000)
        case 1_000...: volumeText = String(format: "$%.0fK", volume / 1_000)
        default: volumeText = String(format: "$%.0f", volume)
        }

        return TrendingEntry(
            date: .now,
            question: question,
            cents: Int((yes * 100).rounded()),
            volume: volumeText
        )
    }
}

struct TrendingMarketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PeakTrendingMarket", provider: TrendingProvider()) { entry in
            TrendingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.05, green: 0.12, blue: 0.14)
                }
        }
        .configurationDisplayName("Trending market")
        .description("Top Polymarket market by 24h volume.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TrendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrendingEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.16, blue: 0.18),
                    Color(red: 0.08, green: 0.22, blue: 0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PEAK")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.55, green: 0.9, blue: 0.78))
                    Spacer()
                    Text(entry.volume)
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer(minLength: 0)

                Text(entry.question)
                    .font(family == .systemSmall ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(family == .systemSmall ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.cents)¢")
                        .font(.system(size: family == .systemSmall ? 28 : 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("Yes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(4)
        }
    }
}

#Preview(as: .systemSmall) {
    TrendingMarketWidget()
} timeline: {
    TrendingEntry(date: .now, question: "Will ETH flip BTC market cap in 2026?", cents: 18, volume: "$890K")
}
