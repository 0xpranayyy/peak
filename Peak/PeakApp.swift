import SwiftUI

@main
struct PeakApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(environment)
                .environmentObject(environment.watchlist)
                .environmentObject(environment.wallet)
                .environmentObject(environment.recentSearches)
                .environmentObject(environment.tradingConfig)
        }
    }
}
