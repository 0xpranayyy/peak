import SwiftUI

struct RootTabView: View {
    @State private var selectedTab: PeakRootTab = .markets
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.peakBrand) private var brand

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
        .tint(brand.mid)
        .onAppear { PeakChrome.apply(for: colorScheme, brand: brand) }
        .onChange(of: colorScheme) { _, scheme in
            PeakChrome.apply(for: scheme, brand: brand)
        }
        // UIKit appearance proxies only affect bars created afterwards, so
        // re-apply when the theme changes rather than relying on the tint above.
        .onChange(of: brand) { _, newBrand in
            PeakChrome.apply(for: colorScheme, brand: newBrand)
        }
        .onReceive(NotificationCenter.default.publisher(for: .peakSelectRootTab)) { note in
            guard let raw = note.userInfo?["tab"] as? String,
                  let tab = PeakRootTab(rawValue: raw) else { return }
            selectedTab = tab
        }
    }
}
