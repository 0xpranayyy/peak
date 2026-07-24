import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let trading: any TradingService
    let watchlist: WatchlistStore
    let wallet: WalletStore

    init(
        trading: any TradingService = StubTradingService(),
        watchlist: WatchlistStore = .shared,
        wallet: WalletStore = .shared
    ) {
        self.trading = trading
        self.watchlist = watchlist
        self.wallet = wallet
    }
}
