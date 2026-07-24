import SwiftUI

/// Place an order via the configured Peak trading proxy (Phase 2).
struct TradeStubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var tradingConfig: TradingConfigStore

    let market: Market
    let sideLabel: String
    let isYes: Bool

    @State private var amountUSD: String = "10"
    @State private var limitPrice: String = ""
    @State private var orderType: OrderKind = .fok
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var didSucceed = false
    @State private var showTradingSettings = false

    enum OrderKind: String, CaseIterable, Identifiable {
        case fok = "FOK"
        case gtc = "GTC"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fok: return "Fill or kill"
            case .gtc: return "Limit (GTC)"
            }
        }
    }

    private var price: Double {
        if let custom = Double(limitPrice), custom > 0, custom < 1 {
            return custom
        }
        return isYes ? market.yesPrice : market.noPrice
    }

    private var shareSize: Double {
        let usd = Double(amountUSD) ?? 0
        guard price > 0 else { return 0 }
        return usd / price
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Market") {
                        Text(market.question)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Side") {
                        Text("Buy \(sideLabel)")
                    }
                    LabeledContent("Price") {
                        Text(PeakFormat.cents(price))
                            .font(.body.monospacedDigit())
                    }
                }

                if tradingConfig.isConfigured {
                    Section("Amount (USD)") {
                        TextField("10", text: $amountUSD)
                            .keyboardType(.decimalPad)
                        Text("≈ \(String(format: "%.2f", shareSize)) shares")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Limit price (optional)") {
                        TextField(PeakFormat.cents(isYes ? market.yesPrice : market.noPrice), text: $limitPrice)
                            .keyboardType(.decimalPad)
                        Text("Leave blank to use the live \(sideLabel) price.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Order type") {
                        Picker("Type", selection: $orderType) {
                            ForEach(OrderKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(didSucceed ? "Order submitted" : "Place order")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting || didSucceed || shareSize <= 0)
                    } footer: {
                        Text("Orders are signed by your Peak trading proxy (CLOB V2). The iOS app never holds the private key.")
                    }
                } else {
                    Section {
                        Text("Trading isn’t connected yet. Run the Peak backend proxy and add its URL + APP_TOKEN.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Set up trading") {
                            showTradingSettings = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(didSucceed ? Color.green : Color.secondary)
                    }
                }
            }
            .navigationTitle("Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTradingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Trading settings")
                }
            }
            .sheet(isPresented: $showTradingSettings) {
                TradingSettingsView()
                    .environmentObject(tradingConfig)
            }
            .onAppear {
                limitPrice = String(format: "%.3f", isYes ? market.yesPrice : market.noPrice)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        guard let tokenID = isYes ? market.yesTokenID : market.noTokenID, !tokenID.isEmpty else {
            message = TradingError.missingToken.localizedDescription
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await env.trading.placeOrder(
                tokenID: tokenID,
                side: .buy,
                price: price,
                size: shareSize,
                negRisk: market.negRisk,
                orderType: orderType.rawValue
            )
            didSucceed = result.success
            message = result.success
                ? "Submitted \(result.status) · \(result.orderID)"
                : "Response: \(result.status)"
        } catch {
            didSucceed = false
            message = error.localizedDescription
        }
    }
}
