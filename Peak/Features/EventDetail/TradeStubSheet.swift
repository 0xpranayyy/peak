import SwiftUI

/// Place an order via Privy session + Peak backend (or legacy proxy).
struct TradeStubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingPath: TradingPathStore

    let market: Market
    let isYes: Bool
    let action: TradeAction
    /// Bid (sell) or ask (buy) quote from the book when available.
    let quotePrice: Double

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
    @State private var showTradingPath = false
    @FocusState private var focusedField: TradeField?

    private enum TradeField: Hashable {
        case amount
        case limit
    }

    private let quickAmounts = ["5", "10", "25", "50", "100"]

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
            && tradingPath.snapshot.path != nil
            && !tradingPath.snapshot.syncReady
    }

    private var setupBlocked: Bool {
        auth.isAuthenticated && tradingPath.needsPathChoice
    }

    private var price: Double {
        if orderType == .gtc, let custom = Double(limitPrice), custom > 0, custom < 1 {
            return custom
        }
        return quotePrice > 0 ? quotePrice : (isYes ? market.yesPrice : market.noPrice)
    }

    private var usdAmount: Double {
        Double(amountUSD) ?? 0
    }

    private var shareSize: Double {
        guard price > 0 else { return 0 }
        return usdAmount / price
    }

    /// Market BUY spends USD; market SELL / limits use share size as CLOB amount.
    private var orderAmount: Double {
        switch action {
        case .buy where orderType == .fok:
            return usdAmount
        case .sell where orderType == .fok:
            return shareSize
        default:
            return shareSize
        }
    }

    private var submitDisabled: Bool {
        isSubmitting
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
                            systemImage: "arrow.triangle.branch",
                            title: "Set up trading",
                            message: "Choose a new wallet or connect one you already use.",
                            accent: action.color
                        ) {
                            Button {
                                showTradingPath = true
                            } label: {
                                PeakPrimaryCTA(
                                    title: "Set up trading",
                                    systemImage: "arrow.triangle.branch",
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
                            systemImage: "arrow.triangle.branch",
                            title: "Finish setup",
                            message: "Your trading wallet isn’t linked yet. Open Account to finish setup, then try again.",
                            accent: action.color
                        ) {
                            Button {
                                showTradingPath = true
                            } label: {
                                PeakPrimaryCTA(
                                    title: "Continue setup",
                                    systemImage: "arrow.triangle.branch",
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
                        TextField("$", text: $amountUSD)
                            .keyboardType(.decimalPad)
                            .font(.title.monospacedDigit().weight(.semibold))
                            .minimumScaleFactor(0.7)
                            .focused($focusedField, equals: .amount)
                            .submitLabel(.done)
                            .accessibilityLabel("Amount in dollars")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickAmounts, id: \.self) { value in
                                    Button("$\(value)") {
                                        amountUSD = value
                                        PeakHaptics.selection()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(amountUSD == value ? action.color : Color.secondary)
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("\(value) dollars")
                                }
                            }
                        }
                        .animation(PeakMotion.snappy, value: amountUSD)

                        Text("≈ \(String(format: "%.2f", shareSize)) shares")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .peakNumeric(value: shareSize)
                    } header: {
                        Text("Amount")
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
                            if !didSucceed, shouldOfferDeposit {
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
            }
            .sheet(isPresented: $showDeposit) {
                DepositSheet()
                    .environmentObject(env)
                    .environmentObject(auth)
                    .environmentObject(tradingPath)
                    .environmentObject(tradingConfig)
            }
            .sheet(isPresented: $showTradingPath) {
                TradingPathSheet()
                    .environmentObject(auth)
                    .environmentObject(tradingConfig)
                    .environmentObject(env.wallet)
                    .environmentObject(tradingPath)
            }
            .onAppear {
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
        let lower = message.lowercased()
        return lower.contains("insufficient")
            || lower.contains("deposit")
            || lower.contains("funds")
            || lower.contains("allowance")
            || lower.contains("not enough")
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
            showTradingPath = true
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
            withAnimation(PeakMotion.soft) {
                didSucceed = false
                message = Self.userFacingTradeError(error)
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
