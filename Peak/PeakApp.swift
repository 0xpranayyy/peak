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
    @StateObject private var peakProfile = PeakProfileStore.shared
    @StateObject private var tradingRegion = TradingRegionStore.shared

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
            .environmentObject(peakProfile)
            .environmentObject(tradingRegion)
            // The themed brand ramp. Note there is no `.id(theme)` here: views
            // that use a brand colour read it from the environment and are
            // invalidated individually, so switching theme keeps scroll
            // position, the selected tab and any open sheet. See
            // `EnvironmentValues.peakBrand`.
            .environment(\.peakBrand, appearance.brand)
            .tint(appearance.brand.mid)
            .preferredColorScheme(appearance.preference.preferredColorScheme)
            .animation(.easeInOut(duration: 0.45), value: categoryPrefs.hasCompletedOnboarding)
            .onOpenURL { url in
                WalletConnectAuthService.shared.handleDeeplink(url)
            }
            // Do NOT configure AppKit here. `AppKit.configure` builds Web3ModalViewModel,
            // whose init eagerly opens a WalletConnect pairing; when the relay is
            // unreachable that throws into a non-throwing context and SIGTRAPs the whole
            // app at launch. `connectWallet()` configures lazily on first real use.
            .task {
                await privyAuth.start()
            }
            // Markets tab owns the first Gamma fetch. Do not warm here — competing
            // /events calls at launch were a major cause of bootstrap timeouts.
            .task {
                PriceAlertMonitor.shared.start()
            }
            .task {
                // Resolve trading eligibility before the user can compose an
                // order that Polymarket would reject.
                await tradingRegion.refreshIfNeeded()
            }
            .sheet(isPresented: Binding(
                get: { privyAuth.showTradingPathSheet && tradingPath.shouldShowSetupSheet },
                set: { privyAuth.showTradingPathSheet = $0 }
            )) {
                TradingPathSheet()
                    .environmentObject(privyAuth)
                    .environmentObject(environment.tradingConfig)
                    .environmentObject(environment.wallet)
                    .environmentObject(tradingPath)
            }
        }
    }
}
