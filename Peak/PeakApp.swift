import SwiftUI

@main
struct PeakApp: App {
    init() {
        CrashReporting.start()
    }

    @StateObject private var environment = AppEnvironment()
    @StateObject private var privyAuth = PrivyAuthService.shared
    @StateObject private var categoryPrefs = CategoryPreferencesStore.shared
    @StateObject private var priceAlerts = PriceAlertStore.shared
    @StateObject private var digest = DailyDigestStore.shared
    @StateObject private var tradingPath = TradingPathStore.shared
    @StateObject private var appearance = AppearanceStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if categoryPrefs.hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(environment)
            .environmentObject(environment.watchlist)
            .environmentObject(environment.wallet)
            .environmentObject(environment.recentSearches)
            .environmentObject(environment.tradingConfig)
            .environmentObject(privyAuth)
            .environmentObject(categoryPrefs)
            .environmentObject(priceAlerts)
            .environmentObject(digest)
            .environmentObject(tradingPath)
            .environmentObject(appearance)
            .preferredColorScheme(appearance.preference.preferredColorScheme)
            .animation(.easeInOut(duration: 0.45), value: categoryPrefs.hasCompletedOnboarding)
            .onOpenURL { url in
                WalletConnectAuthService.shared.handleDeeplink(url)
            }
            .task {
                WalletConnectAuthService.shared.configureIfNeeded()
                await privyAuth.start()
            }
            .task {
                await MarketsCache.shared.warmTrending()
            }
            .task {
                PriceAlertMonitor.shared.start()
            }
            .sheet(isPresented: $privyAuth.showTradingPathSheet) {
                TradingPathSheet()
                    .environmentObject(privyAuth)
                    .environmentObject(environment.tradingConfig)
                    .environmentObject(environment.wallet)
                    .environmentObject(tradingPath)
            }
        }
    }
}
