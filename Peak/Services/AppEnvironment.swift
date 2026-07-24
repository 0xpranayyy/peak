import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let trading: any TradingService
    let watchlist: WatchlistStore
    let wallet: WalletStore
    let recentSearches: RecentSearchStore
    let tradingConfig: TradingConfigStore

    init(
        trading: (any TradingService)? = nil,
        watchlist: WatchlistStore = .shared,
        wallet: WalletStore = .shared,
        recentSearches: RecentSearchStore = .shared,
        tradingConfig: TradingConfigStore = .shared
    ) {
        self.trading = trading ?? RemoteTradingService()
        self.watchlist = watchlist
        self.wallet = wallet
        self.recentSearches = recentSearches
        self.tradingConfig = tradingConfig
    }
}
