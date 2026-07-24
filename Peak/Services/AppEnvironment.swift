import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let trading: any TradingService
    let watchlist: WatchlistStore
    let wallet: WalletStore
    let recentSearches: RecentSearchStore
    let tradingConfig: TradingConfigStore
    let follows: FollowStore

    init(
        trading: (any TradingService)? = nil,
        watchlist: WatchlistStore? = nil,
        wallet: WalletStore? = nil,
        recentSearches: RecentSearchStore? = nil,
        tradingConfig: TradingConfigStore? = nil,
        follows: FollowStore? = nil
    ) {
        self.trading = trading ?? RemoteTradingService()
        self.watchlist = watchlist ?? WatchlistStore.shared
        self.wallet = wallet ?? WalletStore.shared
        self.recentSearches = recentSearches ?? RecentSearchStore.shared
        self.tradingConfig = tradingConfig ?? TradingConfigStore.shared
        self.follows = follows ?? FollowStore.shared
    }
}
