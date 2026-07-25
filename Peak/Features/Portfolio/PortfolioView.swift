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

    func load(env: AppEnvironment) async {
        isLoading = true
        defer { isLoading = false }
        statusBanner = nil

        if env.tradingConfig.isConfigured || (PrivyAuthService.shared.isAuthenticated && env.tradingConfig.hasBackendURL) {
            do {
                let snap = try await env.trading.fetchTradingPortfolio()
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
                return
            } catch {
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
            positions = []
            activity = []
            openOrders = []
            errorMessage = nil
            return
        }

        do {
            async let positionsTask = DataAPI.fetchPositions(wallet: address)
            async let activityTask = DataAPI.fetchActivity(wallet: address, limit: 20)
            positions = try await positionsTask
            activity = (try? await activityTask) ?? []
            errorMessage = nil
        } catch {
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
    @StateObject private var model = PortfolioViewModel()
    @State private var showWalletEditor = false
    @State private var showAccount = false
    @State private var showDeposit = false
    @State private var showTradingPath = false
    @State private var sharePosition: PortfolioPosition?

    private var canTradeLive: Bool {
        auth.isAuthenticated || tradingConfig.isConfigured
    }

    private var needsTradingSetup: Bool {
        auth.isAuthenticated && tradingPath.needsPathChoice
    }

    var body: some View {
        NavigationStack {
            Group {
                if !canTradeLive && !env.wallet.isValid {
                    walletPrompt
                } else if model.isLoading && model.isEmpty && model.cash == nil {
                    PeakSkeletonList(style: .portfolio, rowCount: 6)
                } else if let error = model.errorMessage, model.isEmpty && model.cash == nil {
                    LoadingErrorView(message: error) {
                        Task { await model.load(env: env) }
                    }
                } else {
                    positionsList
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.large)
            .peakChrome()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if canTradeLive, !needsTradingSetup {
                        Button {
                            showDeposit = true
                        } label: {
                            Image(systemName: "arrow.down.to.line.circle")
                        }
                        .accessibilityLabel("Deposit")
                    }
                    Button {
                        showAccount = true
                    } label: {
                        Image(systemName: auth.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle")
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
                    }
                    .presentationDetents([.medium, .large])
                } else {
                    PeakSignInSheet()
                        .environmentObject(auth)
                        .environmentObject(tradingConfig)
                        .environmentObject(env.wallet)
                }
            }
            .sheet(isPresented: $showDeposit) {
                DepositSheet()
                    .environmentObject(env)
            }
            .sheet(isPresented: $showTradingPath) {
                TradingPathSheet()
                    .environmentObject(auth)
                    .environmentObject(tradingConfig)
                    .environmentObject(env.wallet)
                    .environmentObject(tradingPath)
            }
            .sheet(item: $sharePosition) { position in
                SharePositionSheet(position: position)
            }
            .task(id: "\(env.wallet.address ?? "")-\(tradingConfig.isConfigured)-\(auth.isAuthenticated)") {
                model.syncDraft(from: env.wallet)
                await model.load(env: env)
            }
            .onReceive(NotificationCenter.default.publisher(for: .peakTradingPortfolioShouldRefresh)) { _ in
                Task { await model.load(env: env) }
            }
            .refreshable {
                await model.load(env: env)
                PeakHaptics.refresh()
            }
        }
    }

    private var walletPrompt: some View {
        VStack(spacing: 24) {
            Spacer()
            PeakEmptyVisual(kind: .portfolio, size: 96)
            Text("Portfolio")
                .font(.title2.weight(.bold))
            Text("Sign in with a wallet or email to trade, or enter an address to view positions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                showAccount = true
            } label: {
                PeakPrimaryCTA(title: "Sign in", systemImage: "wallet.pass.fill")
            }
            .peakPressable()
            .padding(.horizontal, 40)

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
            if let banner = model.statusBanner {
                Section {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                portfolioSummary
            }

            if needsTradingSetup {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Set up trading", systemImage: "arrow.triangle.branch")
                            .font(.body.weight(.semibold))
                        Text("Choose a new wallet or connect one you already use.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            showTradingPath = true
                        } label: {
                            PeakPrimaryCTA(title: "Set up trading", systemImage: "arrow.triangle.branch")
                        }
                        .peakPressable()
                    }
                    .padding(.vertical, 4)
                }
            } else if model.isZeroCash, canTradeLive {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Add funds to trade", systemImage: "coloncurrencysign.circle")
                            .font(.body.weight(.semibold))
                        Text("Deposit USDC, then open any market to buy or sell.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            showDeposit = true
                        } label: {
                            PeakPrimaryCTA(
                                title: "Deposit",
                                systemImage: "arrow.down.to.line.circle",
                                color: PeakTradeStyle.buy
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(order.side) · \(PeakFormat.cents(order.price))")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(order.side.uppercased() == "BUY" ? PeakTradeStyle.buy : PeakTradeStyle.sell)
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
                }
            }

            if !model.positions.isEmpty {
                Section("Positions") {
                    ForEach(model.positions) { position in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(position.title)
                                .font(.body.weight(.semibold))
                                .lineLimit(2)
                            HStack {
                                Text(position.outcome)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(PeakFormat.usd(position.currentValue))
                                    .font(.body.monospacedDigit().weight(.medium))
                            }
                            .font(.subheadline)
                            HStack {
                                Text("Avg \(PeakFormat.cents(position.avgPrice)) · Now \(PeakFormat.cents(position.currentPrice))")
                                Spacer()
                                Text(String(format: "%+.1f%%", position.percentPnl))
                                    .foregroundStyle(position.percentPnl >= 0 ? PeakTradeStyle.buy : PeakTradeStyle.sell)
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                        .contextMenu {
                            Button {
                                sharePosition = position
                            } label: {
                                Label("Share card", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            } else if !model.isZeroCash, !needsTradingSetup {
                Section {
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
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentColor)
                            .controlSize(.large)
                            .frame(minHeight: 44)
                        } else {
                            Button("Sign in") {
                                showAccount = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentColor)
                            .controlSize(.large)
                            .frame(minHeight: 44)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }
            }

            if !model.activity.isEmpty {
                Section("Recent activity") {
                    ForEach(model.activity) { item in
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
                                    Text("\(side.uppercased()) \(item.outcome ?? "")")
                                        .foregroundStyle(side.uppercased() == "BUY" ? PeakTradeStyle.buy : (side.uppercased() == "SELL" ? PeakTradeStyle.sell : Color.secondary))
                                } else if let outcome = item.outcome {
                                    Text(outcome)
                                }
                                Spacer()
                                if item.usdcSize != 0 {
                                    Text(PeakFormat.usd(item.usdcSize))
                                        .font(.caption.monospacedDigit())
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
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var portfolioSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.usingTradingProxy ? "Portfolio" : "Portfolio value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.usingTradingProxy {
                    Spacer()
                    Text("Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PeakTradeStyle.buy)
                }
            }
            Text(PeakFormat.usd(model.totalValue))
                .font(.largeTitle.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .peakNumeric(value: model.totalValue)
                .accessibilityLabel("Portfolio value \(PeakFormat.usd(model.totalValue))")

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(model.cash.map { PeakFormat.usd($0) } ?? "—")
                        .font(.headline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(model.isZeroCash ? PeakTradeStyle.sell : .primary)
                        .peakNumeric(value: model.cash ?? -1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PnL")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(PeakFormat.usd(model.totalPnl))
                        .font(.headline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(model.totalPnl >= 0 ? PeakTradeStyle.buy : PeakTradeStyle.sell)
                        .peakNumeric(value: model.totalPnl)
                }
                Spacer()
                if canTradeLive, !needsTradingSetup {
                    Button {
                        showDeposit = true
                    } label: {
                        Label("Deposit", systemImage: "arrow.down.to.line.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(PeakTradeStyle.buy)
                    .accessibilityLabel("Deposit funds")
                }
            }

            if let address = model.funder ?? env.wallet.address {
                Text(shorten(address))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Wallet \(address)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func shorten(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
