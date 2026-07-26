import SwiftUI

/// Place an order via Privy session + Peak backend (or legacy proxy).
struct TradeStubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingPath: TradingPathStore
    @EnvironmentObject private var region: TradingRegionStore

    let market: Market
    let isYes: Bool
    let action: TradeAction
    /// Bid (sell) or ask (buy) quote from the book when available.
    let quotePrice: Double
    /// Shares held, when opened from a position. Enables Max / percentage
    /// shortcuts; nil when opened from a market where holdings are unknown.
    var maxShares: Double? = nil

    enum TradeAction {
        case buy
        case sell

        var title: String {
            switch self {
            case .buy: return "Buy"
            case .sell: return "Sell"
            }
        }

        var color: Color {
            switch self {
            case .buy: return PeakTradeStyle.buy
            case .sell: return PeakTradeStyle.sell
            }
        }

        var apiSide: TradeSide {
            switch self {
            case .buy: return .buy
            case .sell: return .sell
            }
        }
    }

    @State private var amountUSD: String = "10"
    @State private var limitPrice: String = ""
    @State private var orderType: OrderKind = .fok
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var didSucceed = false
    @State private var showSignIn = false
    @State private var showDeposit = false
    @State private var showImportKey = false
    @FocusState private var focusedField: TradeField?

    private enum TradeField: Hashable {
        case amount
        case limit
    }

    private let quickAmounts = ["5", "10", "25", "50", "100"]

    private struct QuickChip {
        let label: String
        let value: String
        let accessibility: String
    }

    /// Dollars when buying. When selling from a known position, fractions of the
    /// holding — including Max, which is the only way to fully exit without the
    /// user doing arithmetic against a moving price.
    private var quickChips: [QuickChip] {
        guard sellsInShares else {
            return quickAmounts.map {
                QuickChip(label: "$\($0)", value: $0, accessibility: "\($0) dollars")
            }
        }
        guard let maxShares, maxShares > 0 else { return [] }
        let fmt: (Double) -> String = { String(format: "%.2f", $0) }
        return [
            QuickChip(label: "25%", value: fmt(maxShares * 0.25), accessibility: "25 percent of your shares"),
            QuickChip(label: "50%", value: fmt(maxShares * 0.5), accessibility: "50 percent of your shares"),
            QuickChip(label: "75%", value: fmt(maxShares * 0.75), accessibility: "75 percent of your shares"),
            QuickChip(label: "Max", value: fmt(maxShares), accessibility: "All \(fmt(maxShares)) shares"),
        ]
    }

    enum OrderKind: String, CaseIterable, Identifiable {
        case fok = "FOK"
        case gtc = "GTC"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fok: return "Market"
            case .gtc: return "Limit"
            }
        }
    }

    private var sideLabel: String {
        isYes ? market.yesLabel : market.noLabel
    }

    private var isSignedIn: Bool {
        auth.isAuthenticated || tradingConfig.isConfigured
    }

    private var hasBackend: Bool {
        tradingConfig.hasBackendURL || tradingConfig.isConfigured
    }

    private var canSubmit: Bool {
        isSignedIn && hasBackend
    }

    private var marketClosed: Bool {
        market.closed || !market.active
    }

    private var builderBlocked: Bool {
        auth.isAuthenticated
            && tradingPath.snapshot.path != nil
            && tradingPath.snapshot.syncReady
            && !tradingPath.snapshot.builderConfigured
    }

    /// Path chosen but account wallet not linked / deposit wallet not deployed yet.
    private var walletNotSynced: Bool {
        auth.isAuthenticated
            && !tradingPath.snapshot.imported
            && tradingPath.snapshot.path != nil
            && !tradingPath.snapshot.syncReady
    }

    private var setupBlocked: Bool {
        auth.isAuthenticated
            && !tradingPath.snapshot.imported
            && tradingPath.needsPathChoice
    }

    private var price: Double {
        if orderType == .gtc, let custom = Double(limitPrice), custom > 0, custom < 1 {
            return custom
        }
        return quotePrice > 0 ? quotePrice : (isYes ? market.yesPrice : market.noPrice)
    }

    /// Buys are entered in dollars, sells in shares.
    ///
    /// You hold shares, so asking for a dollar amount to exit forces the user
    /// to do the conversion themselves — and there is no way to express "all of
    /// it". The field means whichever unit the action actually uses; the other
    /// is shown underneath.
    private var sellsInShares: Bool { action == .sell }

    private var enteredValue: Double { Double(amountUSD) ?? 0 }

    /// All unit conversion lives in `TradeAmounts` so it can be tested — see
    /// TradeAmountsTests. The view only supplies inputs.
    private var amounts: TradeAmounts {
        TradeAmounts(
            isSell: sellsInShares,
            isMarket: orderType == .fok,
            price: price,
            entered: enteredValue
        )
    }

    private var usdAmount: Double { amounts.usd }
    private var shareSize: Double { amounts.shares }
    private var orderAmount: Double { amounts.orderAmount }

    /// Polymarket rejects orders from restricted regions, so block them here
    /// rather than after a round trip. Close-only regions may still sell.
    private var regionBlocked: Bool {
        action == .buy ? !region.canTrade : !region.canClose
    }

    private var submitDisabled: Bool {
        isSubmitting
            || regionBlocked
            || didSucceed
            || shareSize <= 0
            || usdAmount <= 0
            || price <= 0
            || price >= 1
            || marketClosed
            || builderBlocked
            || walletNotSynced
            || setupBlocked
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(market.question)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("\(action.title) \(sideLabel)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(action.color)
                            .minimumScaleFactor(0.8)
                            .accessibilityLabel("\(action.title) \(sideLabel)")
                        Spacer()
                        Text(PeakFormat.cents(price))
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .minimumScaleFactor(0.8)
                            .peakNumeric(value: price)
                            .accessibilityLabel("Odds \(PeakFormat.cents(price))")
                    }
                }

                if marketClosed {
                    Section {
                        TradeBlockedPanel(
                            systemImage: "lock.fill",
                            title: "Market closed",
                            message: "This market isn’t accepting orders.",
                            accent: PeakTradeStyle.sell
                        )
                        .peakStatusTransition()
                    }
                } else if !hasBackend {
                    Section {
                        TradeBlockedPanel(
                            systemImage: "exclamationmark.triangle",
                            title: "Trading unavailable",
                            message: "Couldn’t connect. Try again in a moment.",
                            accent: .secondary
                        )
                        .peakStatusTransition()
                    }
                } else if !isSignedIn {
                    Section {
                        TradeBlockedPanel(
                            systemImage: "wallet.pass.fill",
                            title: "Sign in to \(action.title.lowercased())",
                            message: "Connect a wallet, or use email, Apple, or Google.",
                            accent: action.color
                        ) {
                            Button {
                                showSignIn = true
                            } label: {
                                PeakPrimaryCTA(
                                    title: "Sign in",
                                    systemImage: "wallet.pass.fill",
                                    color: action.color
                                )
                            }
                            .peakPressable()
                        }
                        .peakStatusTransition()
                    }
                } else if setupBlocked {
                    Section {
                        TradeBlockedPanel(
                            systemImage: "arrow.clockwise",
                            title: "Finishing setup",
                            message: "We’re linking your trading wallet. Retry, or open Account → Need help?",
                            accent: action.color
                        ) {
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
                                    color: action.color
                                )
                            }
                            .peakPressable()
                        }
                        .peakStatusTransition()
                    }
                } else if walletNotSynced {
                    Section {
                        TradeBlockedPanel(
                            systemImage: "arrow.clockwise",
                            title: "Finish setup",
                            message: "Your trading wallet isn’t linked yet. Retry setup, then try again.",
                            accent: action.color
                        ) {
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
                                    color: action.color
                                )
                            }
                            .peakPressable()
                        }
                        .peakStatusTransition()
                    }
                } else if builderBlocked {
                    Section {
                        TradeBlockedPanel(
                            systemImage: "hourglass",
                            title: "Almost ready",
                            message: "Live trading isn’t available yet. Try again in a moment.",
                            accent: .secondary
                        )
                        .peakStatusTransition()
                    }
                } else if canSubmit {
                    Section {
                        HStack(spacing: 6) {
                            if !sellsInShares {
                                Text("$")
                                    .font(.title.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            TextField(sellsInShares ? "0" : "0", text: $amountUSD)
                                .keyboardType(.decimalPad)
                                .font(.title.monospacedDigit().weight(.semibold))
                                .minimumScaleFactor(0.7)
                                .focused($focusedField, equals: .amount)
                                .submitLabel(.done)
                                .accessibilityLabel(sellsInShares ? "Number of shares to sell" : "Amount in dollars")
                            if sellsInShares {
                                Text("shares")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickChips, id: \.label) { chip in
                                    Button(chip.label) {
                                        amountUSD = chip.value
                                        PeakHaptics.selection()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(amountUSD == chip.value ? action.color : Color.secondary)
                                    .frame(minHeight: 44)
                                    .accessibilityLabel(chip.accessibility)
                                }
                            }
                        }

                        // Always show the other unit, so neither side has to do
                        // the conversion in their head before committing money.
                        Text(sellsInShares
                             ? "≈ \(PeakFormat.usd(usdAmount)) at \(PeakFormat.cents(price))"
                             : "≈ \(String(format: "%.2f", shareSize)) shares at \(PeakFormat.cents(price))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let maxShares, maxShares > 0 {
                            Text("You hold \(String(format: "%.2f", maxShares)) shares")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } header: {
                        Text(sellsInShares ? "Shares to sell" : "Amount to spend")
                    }

                    Section {
                        Picker("Type", selection: $orderType) {
                            ForEach(OrderKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        if orderType == .gtc {
                            TextField("Limit price", text: $limitPrice)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .limit)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } footer: {
                        Text(orderType == .fok
                            ? "Fills at the current price, or cancels if it can’t."
                            : "Waits at your price until filled or you cancel.")
                    }
                    .animation(PeakMotion.soft, value: orderType)

                    if regionBlocked, let restriction = region.restrictionMessage {
                        Section {
                            Label {
                                Text(restriction)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        Button {
                            focusedField = nil
                            Task { await submit() }
                        } label: {
                            PeakPrimaryCTA(
                                title: didSucceed ? "Submitted" : "\(action.title) \(sideLabel)",
                                color: action.color,
                                isLoading: isSubmitting,
                                isEnabled: !submitDisabled
                            )
                        }
                        .peakPressable()
                        .disabled(submitDisabled)
                    }
                }

                if let message {
                    Section {
                        TradeBlockedPanel(
                            systemImage: didSucceed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            title: didSucceed ? "Order submitted" : "Couldn’t place order",
                            message: message,
                            accent: didSucceed ? PeakTradeStyle.buy : PeakTradeStyle.sell
                        ) {
                            if !didSucceed, shouldOfferImport {
                                Button {
                                    showImportKey = true
                                } label: {
                                    PeakPrimaryCTA(
                                        title: "Import private key",
                                        systemImage: "key.fill",
                                        color: action.color
                                    )
                                }
                                .peakPressable()
                            } else if !didSucceed, shouldOfferDeposit {
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
                            } else if !didSucceed {
                                Button {
                                    Task { await submit() }
                                } label: {
                                    PeakPrimaryCTA(
                                        title: "Try again",
                                        systemImage: "arrow.clockwise",
                                        color: action.color,
                                        isLoading: isSubmitting,
                                        isEnabled: !isSubmitting
                                    )
                                }
                                .peakPressable()
                                .disabled(isSubmitting)
                            }
                        }
                        .peakStatusTransition()
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .animation(PeakMotion.soft, value: message)
            .animation(PeakMotion.soft, value: didSucceed)
            .animation(PeakMotion.soft, value: isSignedIn)
            .animation(PeakMotion.soft, value: setupBlocked)
            .animation(PeakMotion.soft, value: walletNotSynced)
            .animation(PeakMotion.soft, value: builderBlocked)
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: orderType) { _, _ in
                if orderType != .gtc { focusedField = .amount }
            }
            .sheet(isPresented: $showSignIn) {
                PeakSignInSheet {
                    // Stay on trade sheet — user can submit immediately.
                }
                .environmentObject(auth)
                .environmentObject(tradingConfig)
                .environmentObject(env.wallet)
                .environmentObject(tradingPath)
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
            .onAppear {
                // The default "10" means ten dollars when buying but ten SHARES
                // when selling, which could be far more than the user holds.
                // Start a sell empty so the amount is always a deliberate choice.
                if sellsInShares { amountUSD = "" }
                limitPrice = String(format: "%.3f", quotePrice > 0 ? quotePrice : price)
                if !isSignedIn {
                    showSignIn = true
                } else if canSubmit {
                    focusAmountSoon()
                }
            }
            .onChange(of: canSubmit) { _, ready in
                if ready { focusAmountSoon() }
            }
            .onChange(of: auth.isAuthenticated) { _, signedIn in
                if signedIn {
                    Task {
                        await auth.finishTradingSetup(wallet: env.wallet, tradingConfig: tradingConfig)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .peakSheetChrome()
    }

    private func focusAmountSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard canSubmit, !didSucceed, !isSubmitting else { return }
            focusedField = .amount
        }
    }

    private var shouldOfferDeposit: Bool {
        guard let message else { return false }
        if shouldOfferImport { return false }
        let lower = message.lowercased()
        return lower.contains("insufficient")
            || lower.contains("deposit")
            || lower.contains("funds")
            || lower.contains("allowance")
            || lower.contains("not enough")
    }

    private var shouldOfferImport: Bool {
        if tradingPath.snapshot.needsImport || tradingPath.shouldOfferImport { return true }
        guard let message else { return false }
        return PeakUserCopy.isImportWalletMessage(message)
            || PeakUserCopy.isWalletAuthFailure(message)
    }

    private func submit() async {
        withAnimation(PeakMotion.soft) {
            message = nil
            didSucceed = false
        }

        guard !marketClosed else {
            withAnimation(PeakMotion.soft) {
                message = TradingError.marketClosed.localizedDescription
            }
            return
        }
        guard let tokenID = isYes ? market.yesTokenID : market.noTokenID, !tokenID.isEmpty else {
            withAnimation(PeakMotion.soft) {
                message = TradingError.missingToken.localizedDescription
            }
            return
        }
        guard hasBackend else {
            withAnimation(PeakMotion.soft) {
                message = TradingError.notConfigured.localizedDescription
            }
            return
        }
        guard canSubmit else {
            showSignIn = true
            return
        }
        if setupBlocked {
            withAnimation(PeakMotion.soft) {
                message = TradingError.setupRequired.localizedDescription
            }
            return
        }
        if walletNotSynced {
            withAnimation(PeakMotion.soft) {
                message = TradingError.setupRequired.localizedDescription
            }
            Task {
                await auth.finishTradingSetup(wallet: env.wallet, tradingConfig: tradingConfig)
            }
            return
        }
        if builderBlocked {
            withAnimation(PeakMotion.soft) {
                message = TradingError.builderNotReady.localizedDescription
            }
            return
        }
        guard usdAmount > 0, shareSize > 0, price > 0, price < 1 else {
            withAnimation(PeakMotion.soft) {
                message = TradingError.invalidAmount.localizedDescription
            }
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await env.trading.placeOrder(
                tokenID: tokenID,
                side: action.apiSide,
                price: price,
                size: shareSize,
                amount: orderAmount,
                negRisk: market.negRisk,
                orderType: orderType.rawValue
            )
            guard result.success else {
                withAnimation(PeakMotion.soft) {
                    didSucceed = false
                    message = "Order wasn’t accepted. Try again."
                }
                return
            }
            withAnimation(PeakMotion.soft) {
                didSucceed = true
                message = "Your order was submitted."
            }
            PeakHaptics.success()
            focusedField = nil
            NotificationCenter.default.post(name: .peakTradingPortfolioShouldRefresh, object: nil)
            // Best-effort sync so Portfolio shows the fill / open order promptly.
            Task {
                _ = try? await env.trading.fetchTradingPortfolio()
                NotificationCenter.default.post(name: .peakTradingPortfolioShouldRefresh, object: nil)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            let facing = Self.userFacingTradeError(error)
            if PeakUserCopy.isImportWalletMessage(facing) || PeakUserCopy.isWalletAuthFailure(facing) {
                TradingPathStore.shared.apply(server: [
                    "needsImport": true,
                    "imported": false,
                    "code": "import_wallet_required",
                ])
            }
            withAnimation(PeakMotion.soft) {
                didSucceed = false
                message = facing
            }
            PeakHaptics.error()
        }
    }

    private static func userFacingTradeError(_ error: Error) -> String {
        PeakUserCopy.fromError(error, fallback: "Couldn’t place order. Try again.")
    }
}

/// Single status panel for trade-sheet blockers / results.
private struct TradeBlockedPanel<Action: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var accent: Color = .secondary
    @ViewBuilder var action: () -> Action

    init(
        systemImage: String,
        title: String,
        message: String,
        accent: Color = .secondary,
        @ViewBuilder action: @escaping () -> Action = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.accent = accent
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
