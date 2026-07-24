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

    func syncDraft(from wallet: WalletStore) {
        if draftAddress.isEmpty {
            draftAddress = wallet.address ?? ""
        }
    }

    func load(env: AppEnvironment) async {
        isLoading = true
        defer { isLoading = false }
        statusBanner = nil

        if env.tradingConfig.isConfigured {
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
                if let funder = snap.funder, !env.wallet.isValid {
                    env.wallet.save(funder)
                    draftAddress = funder
                }
                return
            } catch {
                // Fall through to public wallet lookup if proxy fails.
                statusBanner = "Trading proxy unavailable — showing public wallet data."
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
            errorMessage = error.localizedDescription
        }
    }

    func cancelOrder(id: String, env: AppEnvironment) async {
        do {
            try await env.trading.cancelOrder(id: id)
            openOrders.removeAll { $0.id == id }
            statusBanner = "Order canceled."
        } catch {
            statusBanner = error.localizedDescription
        }
    }
}

struct PortfolioView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @StateObject private var model = PortfolioViewModel()
    @State private var showWalletEditor = false
    @State private var showTradingSettings = false
    @State private var showDeposit = false

    var body: some View {
        NavigationStack {
            Group {
                if !tradingConfig.isConfigured && !env.wallet.isValid {
                    walletPrompt
                } else if model.isLoading && model.isEmpty {
                    ProgressView("Loading portfolio…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage, model.isEmpty {
                    LoadingErrorView(message: error) {
                        Task { await model.load(env: env) }
                    }
                } else if model.isEmpty {
                    EmptyStateView(
                        systemImage: "briefcase",
                        title: "No open positions",
                        message: tradingConfig.isConfigured
                            ? "Your trading wallet has no positions yet. Deposit pUSD to get started."
                            : "This wallet has no positions on Polymarket right now."
                    )
                } else {
                    positionsList
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Portfolio")
            .peakChrome()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTradingSettings = true
                    } label: {
                        Image(systemName: tradingConfig.isConfigured ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                    }
                    .accessibilityLabel("Trading settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if tradingConfig.isConfigured {
                        Button {
                            showDeposit = true
                        } label: {
                            Image(systemName: "arrow.down.to.line.circle")
                        }
                        .accessibilityLabel("Deposit")
                    }
                    Button {
                        model.syncDraft(from: env.wallet)
                        showWalletEditor = true
                    } label: {
                        Image(systemName: "wallet.pass")
                    }
                    .accessibilityLabel("Wallet")
                }
            }
            .sheet(isPresented: $showWalletEditor) {
                walletEditor
            }
            .sheet(isPresented: $showTradingSettings) {
                TradingSettingsView()
            }
            .sheet(isPresented: $showDeposit) {
                DepositSheet()
                    .environmentObject(env)
            }
            .task(id: "\(env.wallet.address ?? "")-\(tradingConfig.isConfigured)") {
                model.syncDraft(from: env.wallet)
                await model.load(env: env)
            }
            .refreshable {
                await model.load(env: env)
            }
        }
    }

    private var walletPrompt: some View {
        ContentUnavailableView {
            Label("Add a wallet", systemImage: "wallet.pass")
        } description: {
            Text("Paste any Polymarket wallet for a read-only view, or connect the trading proxy to manage live orders.")
        } actions: {
            Button("Add Wallet") {
                model.draftAddress = ""
                showWalletEditor = true
            }
            .buttonStyle(.borderedProminent)
            Button("Set up trading") {
                showTradingSettings = true
            }
            .buttonStyle(.bordered)
        }
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.usingTradingProxy ? "Trading portfolio" : "Portfolio value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if model.usingTradingProxy {
                            Spacer()
                            Text("Live")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    Text(PeakFormat.usd(model.totalValue))
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                    if let cash = model.cash {
                        Text("Cash \(PeakFormat.usd(cash))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("PnL \(PeakFormat.usd(model.totalPnl))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(model.totalPnl >= 0 ? Color.green : Color.red)
                    if let address = model.funder ?? env.wallet.address {
                        Text(shorten(address))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            if !model.openOrders.isEmpty {
                Section("Open orders") {
                    ForEach(model.openOrders) { order in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(order.side) · \(PeakFormat.cents(order.price))")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
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
                                    .foregroundStyle(position.percentPnl >= 0 ? Color.green : Color.red)
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
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

    private var walletEditor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0x…", text: $model.draftAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .keyboardType(.asciiCapable)
                } header: {
                    Text("Wallet address")
                } footer: {
                    Text("Used for public portfolio lookup when the trading proxy isn’t connected.")
                }

                if env.wallet.address != nil {
                    Section {
                        Button("Remove wallet", role: .destructive) {
                            env.wallet.clear()
                            model.draftAddress = ""
                            model.positions = []
                            model.activity = []
                            model.openOrders = []
                            showWalletEditor = false
                        }
                    }
                }
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showWalletEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        env.wallet.save(model.draftAddress)
                        showWalletEditor = false
                    }
                    .disabled(!isDraftValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isDraftValid: Bool {
        let lower = model.draftAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("0x") && lower.count == 42
    }

    private func shorten(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
