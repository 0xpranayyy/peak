import SwiftUI

struct RootTabView: View {
    @State private var selectedTab: PeakRootTab = .markets

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Markets", systemImage: "chart.line.uptrend.xyaxis", value: .markets) {
                MarketsView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchView()
            }
            Tab("Portfolio", systemImage: "briefcase", value: .portfolio) {
                PortfolioView()
            }
            Tab("Watchlist", systemImage: "star", value: .watchlist) {
                WatchlistView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .peakSelectRootTab)) { note in
            guard let raw = note.userInfo?["tab"] as? String,
                  let tab = PeakRootTab(rawValue: raw) else { return }
            selectedTab = tab
        }
    }
}
