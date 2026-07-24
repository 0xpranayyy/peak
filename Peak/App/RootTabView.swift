import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Markets", systemImage: "chart.line.uptrend.xyaxis") {
                MarketsView()
            }
            Tab("Search", systemImage: "magnifyingglass") {
                SearchView()
            }
            Tab("Watchlist", systemImage: "star") {
                WatchlistView()
            }
            Tab("Portfolio", systemImage: "briefcase") {
                PortfolioView()
            }
        }
    }
}
