import SwiftUI

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published var positions: [PortfolioPosition] = []
    @Published var activity: [PortfolioActivity] = []
    @Published var openOrders: [OpenOrder] = []
    @Published var cash: Double?
    @Published var reportedValue: Double?
    @Published var funder: String?
    @Published var usingTradingProxy = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var draftAddress = ""
    @Published var statusBanner: String?
    @Published var needsImportWallet = false

    private var loadGeneration = 0

    var totalValue: Double {
        reportedValue ?? positions.reduce(0) { $0 + $1.currentValue }
    }

    var totalPnl: Double {
        positions.reduce(0) { $0 + $1.cashPnl }
    }

    var isEmpty: Bool {
        positions.isEmpty && activity.isEmpty && openOrders.isEmpty
    }

    var hasCash: Bool {
        (cash ?? 0) > 0.000_001
    }

    var isZeroCash: Bool {
        usingTradingProxy && !hasCash
    }

    func syncDraft(from wallet: WalletStore) {
        if draftAddress.isEmpty {
            draftAddress = wallet.address ?? ""
        }
    }

    /// Sign-in / import flips auth + wallet several times — coalesce into one fetch.
    func load(env: AppEnvironment, debounceNanoseconds: UInt64 = 0) async {
        loadGeneration += 1
        let generation = loadGeneration
        if debounceNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
        }
        guard !Task.isCancelled, generation == loadGeneration else { return }
        await performLoad(env: env, generation: generation)
    }

    private func performLoad(env: AppEnvironment, generation: Int) async {
        let showSpinner = isEmpty && cash == nil
        if showSpinner { isLoading = true }
        defer {
            if generation == loadGeneration, showSpinner {
                isLoading = false
            }
        }
        statusBanner = nil
        needsImportWallet = false

        if env.tradingConfig.isConfigured || (PrivyAuthService.shared.isAuthenticated && env.tradingConfig.hasBackendURL) {
            do {
                let snap = try await env.trading.fetchTradingPortfolio()
                guard generation == loadGeneration else { return }
                usingTradingProxy = true
                positions = snap.positions
                activity = snap.activity
                openOrders = snap.openOrders
                cash = snap.cash
                reportedValue = snap.totalValue
                funder = snap.funder
                errorMessage = nil
                TradingPathStore.shared.apply(server: snap.pathFlags.asServerDict())
                if let funder = snap.funder, !env.wallet.isValid {
                    env.wallet.save(funder)
                    draftAddress = funder
                }
                PeakProfileStore.shared.refresh(
                    primary: PrivyAuthService.shared.walletAddress ?? snap.funder ?? env.wallet.address,
                    secondary: TradingPathStore.shared.snapshot.accountWallet ?? snap.funder
                )
                needsImportWallet = snap.needsImport
                    || TradingPathStore.shared.snapshot.needsImport
                    || PeakUserCopy.isImportWalletMessage(snap.cashError ?? "")
                    || ((snap.cashErrorCode ?? "").lowercased() == "import_wallet_required")
                if needsImportWallet {
                    TradingPathStore.shared.apply(server: [
                        "needsImport": true,
                        "cashErrorCode": snap.cashErrorCode ?? "import_wallet_required",
                    ])
                }
                if snap.cash == nil, let cashError = snap.cashError, !cashError.isEmpty {
                    statusBanner = PeakUserCopy.sanitizeOrderOrServerCopy(
                        cashError,
                        fallback: "Couldn’t sync cash balance. Try again."
                    )
                }
                return
            } catch {
                guard generation == loadGeneration else { return }
                // Fall through to public wallet lookup if proxy fails.
                statusBanner = "Couldn’t load live portfolio. Showing public data."
                usingTradingProxy = false
            }
        } else {
            usingTradingProxy = false
            openOrders = []
            cash = nil
            reportedValue = nil
            funder = nil
        }

        guard env.wallet.isValid, let address = env.wallet.address else {
            guard generation == loadGeneration else { return }
            positions = []
            activity = []
            openOrders = []
            errorMessage = nil
            return
        }

        do {
            async let positionsTask = DataAPI.fetchPositions(wallet: address)
            async let activityTask = DataAPI.fetchActivity(wallet: address, limit: 20)
            let nextPositions = try await positionsTask
            let nextActivity = (try? await activityTask) ?? []
            guard generation == loadGeneration else { return }
            positions = nextPositions
            activity = nextActivity
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t load portfolio. Try again.")
        }
    }

    func cancelOrder(id: String, env: AppEnvironment) async {
        do {
            try await env.trading.cancelOrder(id: id)
            openOrders.removeAll { $0.id == id }
            statusBanner = "Order canceled."
        } catch {
            statusBanner = PeakUserCopy.fromError(error, fallback: "Couldn’t cancel that order. Try again.")
        }
    }
}

struct PortfolioView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingPath: TradingPathStore
    @EnvironmentObject private var peakProfile: PeakProfileStore
    @StateObject private var model = PortfolioViewModel()
    @State private var showWalletEditor = false
    @State private var showAccount = false
    @State private var showDeposit = false
    @State private var showImportKey = false
    @State private var sharePosition: PortfolioPosition?
    /// Resolved market for a tapped position, presented as a sell sheet.
    @State private var sellTarget: SellTarget?
    @State private var loadingSellFor: String?
    @State private var sellLoadError: String?

    /// Carries the REAL market, resolved from Gamma. Assembling one from the
    /// position would mean guessing negRisk and the token ids, which feed order
    /// placement — a wrong guess silently misprices or rejects the trade.
    struct SellTarget: Identifiable {
        let id: String
        let market: Market
        let isYes: Bool
        let quotePrice: Double
        let shares: Double
    }
    @AppStorage("peak.portfolio.linkBanner.dismissed") private var linkBannerDismissed = false

    private var canTradeLive: Bool {
        auth.isAuthenticated || tradingConfig.isConfigured
    }

    private var needsTradingSetup: Bool {
        auth.isAuthenticated
            && !tradingPath.snapshot.imported
            && tradingPath.shouldShowSetupSheet
    }

    /// Signed in / trading proxy ready: cash is the hero number (wallet-style).
    private var showCashHero: Bool {
        canTradeLive && model.usingTradingProxy
    }

    private var showLinkBanner: Bool {
        guard auth.isAuthenticated, !linkBannerDismissed else { return false }
        if tradingPath.snapshot.imported { return false }
        if tradingPath.needsPathChoice { return true }
        if tradingPath.snapshot.path == .existing, !tradingPath.snapshot.syncReady { return true }
        if tradingPath.snapshot.needsImport || model.needsImportWallet { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if !canTradeLive && !env.wallet.isValid {
                    walletPrompt
                } else if model.isLoading && model.isEmpty && model.cash == nil {
                    List {
                        Section {
                            PeakPageHeader(title: "Portfolio")
                                .peakPageHeaderRow()
                        }
                        Section {
                            PeakSkeletonSummary()
                                .listRowBackground(PeakCanvas.elevated)
                        }
                        Section {
                            ForEach(0..<4, id: \.self) { _ in
                                PeakSkeletonRow()
                                    .listRowBackground(PeakCanvas.elevated)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Loading")
                } else if let error = model.errorMessage, model.isEmpty && model.cash == nil {
                    LoadingErrorView(message: error) {
                        Task { await model.load(env: env) }
                    }
                } else {
                    positionsList
                }
            }
            .background(PeakMaterialBackground())
            .peakRootTab("Portfolio")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if canTradeLive, !needsTradingSetup {
                        Button {
                            showDeposit = true
                        } label: {
                            PeakToolbarCircle(systemImage: "arrow.down.to.line")
                        }
                        .accessibilityLabel("Deposit")
                    }
                    Button {
                        showAccount = true
                    } label: {
                        if let profile = peakProfile.profile, profile.profileImageURL != nil || profile.hasIdentity {
                            PeakAvatar(
                                imageURL: profile.profileImageURL,
                                title: profile.displayName,
                                size: 34,
                                verified: profile.verifiedBadge
                            )
                        } else {
                            PeakToolbarCircle(
                                systemImage: auth.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle",
                                emphasized: auth.isAuthenticated
                            )
                        }
                    }
                    .accessibilityLabel("Account")
                }
            }
            .sheet(isPresented: $showWalletEditor) {
                NavigationStack {
                    WalletSettingsView()
                        .environmentObject(env.wallet)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showWalletEditor = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAccount) {
                if auth.isAuthenticated {
                    NavigationStack {
                        AccountView(isPresentedModally: true)
                            .environmentObject(auth)
                            .environmentObject(tradingConfig)
                            .environmentObject(env.wallet)
                            .environmentObject(tradingPath)
                            .environmentObject(peakProfile)
                    }
                    .presentationDetents([.medium, .large])
                } else {
                    PeakSignInSheet()
                        .environmentObject(auth)
                        .environmentObject(tradingConfig)
                        .environmentObject(env.wallet)
                        .environmentObject(tradingPath)
                }
            }
            .sheet(isPresented: $showDeposit) {
                DepositSheet()
                    .environmentObject(env)
                    .environmentObject(auth)
                    .environmentObject(tradingPath)
                    .environmentObject(tradingConfig)
            }
            .sheet(isPresented: $showImportKey) {
                ImportTradingWalletSheet()
                    .environmentObject(auth)
                    .environmentObject(tradingConfig)
                    .environmentObject(env.wallet)
                    .environmentObject(tradingPath)
            }
            .sheet(item: $sellTarget) { target in
                TradeStubSheet(
                    market: target.market,
                    isYes: target.isYes,
                    action: .sell,
                    quotePrice: target.quotePrice,
                    maxShares: target.shares
                )
                .environmentObject(env)
                .environmentObject(env.tradingConfig)
                .environmentObject(auth)
                .environmentObject(tradingPath)
                .environmentObject(TradingRegionStore.shared)
            }
            .alert("Couldn’t open this position", isPresented: Binding(
                get: { sellLoadError != nil },
                set: { if !$0 { sellLoadError = nil } }
            )) {
                Button("OK", role: .cancel) { sellLoadError = nil }
            } message: {
                Text(sellLoadError ?? "")
            }
            .sheet(item: $sharePosition) { position in
                SharePositionSheet(position: position)
            }
            .task(id: "\(env.wallet.address ?? "")-\(tradingConfig.isConfigured)-\(auth.isAuthenticated)-\(auth.walletAddress ?? "")") {
                model.syncDraft(from: env.wallet)
                peakProfile.refresh(
                    primary: auth.walletAddress ?? env.wallet.address,
                    secondary: tradingPath.snapshot.accountWallet ?? model.funder
                )
                // Auth/import flips this id several times — coalesce into one portfolio fetch.
                await model.load(env: env, debounceNanoseconds: 280_000_000)
            }
            .onReceive(NotificationCenter.default.publisher(for: .peakTradingPortfolioShouldRefresh)) { _ in
                Task { await model.load(env: env, debounceNanoseconds: 120_000_000) }
            }
            .refreshable {
                await model.load(env: env)
                PeakHaptics.refresh()
            }
        }
    }

    private var walletPrompt: some View {
        VStack(spacing: 0) {
            PeakPageHeader(title: "Portfolio")
                .padding(.horizontal, PeakLayout.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            PeakEmptyVisual(kind: .portfolio, size: 96)
            Text("Sign in with a wallet or email to trade, or enter an address to view positions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 16)

            Button {
                showAccount = true
            } label: {
                PeakPrimaryCTA(title: "Sign in", systemImage: "wallet.pass.fill", color: PeakBrand.mid)
            }
            .peakPressable()
            .padding(.horizontal, 40)
            .padding(.top, 20)

            Button("Enter address") {
                showWalletEditor = true
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var positionsList: some View {
        List {
            Section {
                PeakPageHeader(title: "Portfolio")
                    .peakPageHeaderRow()
            }

            if let banner = model.statusBanner {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(banner)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.needsImportWallet, tradingPath.shouldOfferImport {
                            Button {
                                showImportKey = true
                            } label: {
                                Label("Import private key", systemImage: "key.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentColor)
                        }
                    }
                }
            }

            if showLinkBanner {
                Section {
                    linkPolymarketBanner
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            Section {
                portfolioSummary
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(PeakCanvas.elevated)
            }

            if needsTradingSetup {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Finishing setup")
                            .font(.body.weight(.semibold))
                        Text("Linking your wallet. You can retry from Account if this takes a moment.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            Task {
                                await auth.finishTradingSetup(
                                    wallet: env.wallet,
                                    tradingConfig: tradingConfig
                                )
                            }
                        } label: {
                            PeakPrimaryCTA(
                                title: "Retry setup",
                                systemImage: "arrow.clockwise",
                                color: PeakBrand.mid
                            )
                        }
                        .peakPressable()
                    }
                    .padding(.vertical, 4)
                }
            }

            if !model.openOrders.isEmpty {
                Section("Open orders") {
                    ForEach(model.openOrders) { order in
                        openOrderRow(order)
                    }
                }
            }

            if !model.positions.isEmpty {
                Section("Positions") {
                    ForEach(model.positions) { position in
                        positionRow(position)
                    }
                }
            } else if !model.isZeroCash, !needsTradingSetup {
                Section {
                    emptyPositions
                }
            }

            if !model.activity.isEmpty {
                Section("Recent activity") {
                    ForEach(model.activity) { item in
                        activityRow(item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(PeakCanvas.hairline)
    }

    private var linkPolymarketBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.needsImportWallet || tradingPath.snapshot.needsImport
                  ? "key.fill"
                  : "link.circle.fill")
                .font(.title3)
                .foregroundStyle(PeakBrand.mid)
                .accessibilityHidden(true)

            Text(
                model.needsImportWallet || tradingPath.snapshot.needsImport
                    ? PeakUserCopy.importWalletRequired
                    : "Already on Polymarket? Import your wallet under Account → Need help?"
            )
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button {
                linkBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(PeakLayout.stack + 2)
        .background(PeakCanvas.inset, in: PeakLayout.cardShape)
        .overlay {
            PeakLayout.cardShape.strokeBorder(PeakCanvas.hairline, lineWidth: 1)
        }
        .contentShape(PeakLayout.cardShape)
        .onTapGesture {
            if (model.needsImportWallet || tradingPath.snapshot.needsImport), tradingPath.shouldOfferImport {
                showImportKey = true
            } else {
                Task {
                    await auth.finishTradingSetup(wallet: env.wallet, tradingConfig: tradingConfig)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(
            (model.needsImportWallet || tradingPath.snapshot.needsImport) && tradingPath.shouldOfferImport
                ? "Opens import wallet"
                : "Retries wallet setup"
        )
        .peakAppear()
    }

    private var portfolioSummary: some View {
        VStack(alignment: .leading, spacing: PeakLayout.stack) {
            identityRow

            HStack(alignment: .firstTextBaseline) {
                Text(showCashHero ? "Cash" : "Portfolio value")
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if model.usingTradingProxy {
                    Text("Live")
                        .font(.caption2.weight(.bold))
                        .tracking(0.3)
                        .foregroundStyle(PeakBrand.mid)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            PeakBrand.mid.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: PeakLayout.badgeRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: PeakLayout.badgeRadius, style: .continuous)
                                .strokeBorder(PeakCanvas.brandRim, lineWidth: 1)
                        }
                }
            }

            Text(PeakFormat.usd(showCashHero ? (model.cash ?? 0) : model.totalValue))
                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .peakNumeric(value: showCashHero ? (model.cash ?? 0) : model.totalValue)
                .accessibilityLabel(
                    showCashHero
                        ? "Cash \(PeakFormat.usd(model.cash ?? 0))"
                        : "Portfolio value \(PeakFormat.usd(model.totalValue))"
                )

            HStack(alignment: .top, spacing: 0) {
                if showCashHero {
                    summaryMetric(
                        label: "Portfolio",
                        value: PeakFormat.usd(model.totalValue),
                        valueKey: model.totalValue
                    )
                    metricDivider
                } else if model.cash != nil {
                    summaryMetric(
                        label: "Cash",
                        value: PeakFormat.usd(model.cash ?? 0),
                        valueKey: model.cash ?? 0,
                        tint: model.isZeroCash ? PeakTradeStyle.sell : nil
                    )
                    metricDivider
                }

                summaryMetric(
                    label: "PnL",
                    value: signedUSD(model.totalPnl),
                    valueKey: model.totalPnl,
                    tint: model.totalPnl >= 0 ? PeakTradeStyle.buy : PeakTradeStyle.sell
                )

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            if canTradeLive, !needsTradingSetup {
                Button {
                    showDeposit = true
                } label: {
                    PeakPrimaryCTA(
                        title: "Deposit",
                        systemImage: "arrow.down.to.line.circle",
                        color: PeakBrand.mid
                    )
                }
                .peakPressable()
                .accessibilityLabel("Deposit funds")

                if model.isZeroCash {
                    Text("Deposit USDC, then open any market to buy or sell.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let address = model.funder ?? env.wallet.address,
               peakProfile.profile?.hasIdentity != true,
               !auth.isAuthenticated {
                Text(shorten(address))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Wallet \(address)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var identityRow: some View {
        let address = auth.walletAddress ?? model.funder ?? env.wallet.address
        let name = peakProfile.displayName(fallbackAddress: address, email: auth.email)
        let showIdentity = auth.isAuthenticated || peakProfile.profile?.hasIdentity == true || address != nil
        if showIdentity {
            Button {
                showAccount = true
            } label: {
                HStack(spacing: 12) {
                    PeakAvatar(
                        imageURL: peakProfile.profile?.profileImageURL,
                        title: name,
                        size: 44,
                        verified: peakProfile.profile?.verifiedBadge ?? false
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let address {
                            Text(shorten(address))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if let email = auth.email, name != email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account, \(name)")
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(PeakCanvas.hairline)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private func summaryMetric(
        label: String,
        value: String,
        valueKey: Double,
        tint: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint ?? .primary)
                .peakNumeric(value: valueKey)
        }
    }

    private func openOrderRow(_ order: OpenOrder) -> some View {
        let isBuy = order.side.uppercased() == "BUY"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(order.side) · \(PeakFormat.cents(order.price))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isBuy ? PeakTradeStyle.buy : PeakTradeStyle.sell)
                Spacer()
                Button("Cancel", role: .destructive) {
                    Task { await model.cancelOrder(id: order.id, env: env) }
                }
                .font(.caption.weight(.semibold))
            }
            Text("Size \(String(format: "%.2f", order.remaining)) left of \(String(format: "%.2f", order.originalSize))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let status = order.status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func positionRow(_ position: PortfolioPosition) -> some View {
        let pnlPositive = position.cashPnl >= 0
        let pnlColor = pnlPositive ? PeakTradeStyle.buy : PeakTradeStyle.sell
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(position.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(PeakFormat.usd(position.currentValue))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(position.outcome)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(signedUSD(position.cashPnl))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(pnlColor)
                Text(String(format: "%+.1f%%", position.percentPnl))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(pnlColor)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            Text("Avg \(PeakFormat.cents(position.avgPrice)) · Now \(PeakFormat.cents(position.currentPrice))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, PeakLayout.rowPadding - 2)
        .listRowBackground(PeakCanvas.elevated)
        .overlay(alignment: .trailing) {
            if loadingSellFor == position.id {
                ProgressView().controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await openSell(position) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens sell for this position")
        .contextMenu {
            Button {
                Task { await openSell(position) }
            } label: {
                Label("Sell", systemImage: "arrow.down.circle")
            }
            Button {
                sharePosition = position
            } label: {
                Label("Share card", systemImage: "square.and.arrow.up")
            }
        }
    }

    /// Resolve a position back to its live market before offering to sell.
    ///
    /// Positions carry eventSlug, not an event id, and no negRisk or token ids
    /// beyond the held asset — all of which order placement depends on. Fetching
    /// the real event keeps the sell on the same data path as a market-initiated
    /// trade instead of a reconstruction that could be subtly wrong.
    @MainActor
    private func openSell(_ position: PortfolioPosition) async {
        guard loadingSellFor == nil else { return }
        guard let slug = position.eventSlug, !slug.isEmpty else {
            sellLoadError = "This position isn’t linked to a market yet."
            return
        }
        loadingSellFor = position.id
        defer { loadingSellFor = nil }

        do {
            let event = try await GammaAPI.fetchEvent(slug: slug)
            // Match on the token actually held — an event can hold many markets,
            // and selling the wrong one would be silent and expensive.
            let held = position.asset
            let match = event.markets.first {
                $0.yesTokenID == held || $0.noTokenID == held
            } ?? event.markets.first { $0.conditionId == position.conditionId }

            guard let market = match else {
                sellLoadError = "Couldn’t match this position to a market."
                return
            }
            let isYes = market.yesTokenID == held
                ? true
                : (market.noTokenID == held ? false : position.outcome.caseInsensitiveCompare("Yes") == .orderedSame)

            sellTarget = SellTarget(
                id: position.id,
                market: market,
                isYes: isYes,
                quotePrice: isYes ? market.yesPrice : market.noPrice,
                shares: position.size
            )
            PeakHaptics.selection()
        } catch {
            sellLoadError = PeakUserCopy.fromError(error, fallback: "Couldn’t load this market. Try again.")
        }
    }

    private var emptyPositions: some View {
        VStack(spacing: 12) {
            PeakEmptyVisual(kind: .portfolio, size: 64)
            Text(canTradeLive
                ? "No open positions yet"
                : "No positions for this address")
                .font(.subheadline.weight(.semibold))
            Text(canTradeLive
                ? "Buy a market to get started."
                : "Try another address, or sign in to trade.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if canTradeLive {
                Button("Browse markets") {
                    PeakRootTab.select(.markets)
                }
                .buttonStyle(.bordered)
                .tint(PeakBrand.mid)
                .controlSize(.large)
                .frame(minHeight: 44)
            } else {
                Button("Sign in") {
                    showAccount = true
                }
                .buttonStyle(.borderedProminent)
                .tint(PeakBrand.mid)
                .controlSize(.large)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .listRowBackground(Color.clear)
    }

    private func activityRow(_ item: PortfolioActivity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Text(item.type.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let side = item.side {
                    let upper = side.uppercased()
                    Text("\(upper) \(item.outcome ?? "")")
                        .foregroundStyle(
                            upper == "BUY" ? PeakTradeStyle.buy
                                : (upper == "SELL" ? PeakTradeStyle.sell : Color.secondary)
                        )
                } else if let outcome = item.outcome {
                    Text(outcome)
                }
                Spacer()
                if item.usdcSize != 0 {
                    Text(PeakFormat.usd(item.usdcSize))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(
                            item.usdcSize >= 0 ? PeakTradeStyle.buy : PeakTradeStyle.sell
                        )
                } else if item.price > 0 {
                    Text(PeakFormat.cents(item.price))
                        .font(.caption.monospacedDigit())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func signedUSD(_ value: Double) -> String {
        if value > 0 { return "+\(PeakFormat.usd(value))" }
        return PeakFormat.usd(value)
    }

    private func shorten(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
