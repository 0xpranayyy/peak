import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let trading: any TradingService
    let watchlist: WatchlistStore
    let wallet: WalletStore
    let recentSearches: RecentSearchStore

    init(
        trading: any TradingService = StubTradingService(),
        watchlist: WatchlistStore = .shared,
        wallet: WalletStore = .shared,
        recentSearches: RecentSearchStore = .shared
    ) {
        self.trading = trading
        self.watchlist = watchlist
        self.wallet = wallet
        self.recentSearches = recentSearches
    }
}
