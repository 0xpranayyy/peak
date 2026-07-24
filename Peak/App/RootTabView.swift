import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            MarketsView()
                .tabItem {
                    Label("Markets", systemImage: "chart.line.uptrend.xyaxis")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "star")
                }

            PortfolioView()
                .tabItem {
                    Label("Portfolio", systemImage: "briefcase")
                }
        }
    }
}
