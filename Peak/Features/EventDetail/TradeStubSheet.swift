import SwiftUI

/// Phase-2 stub: Yes/No opens this sheet; no orders are placed.
struct TradeStubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment

    let market: Market
    let sideLabel: String
    let isYes: Bool

    @State private var amount: String = "10"
    @State private var message: String?

    private var price: Double {
        isYes ? market.yesPrice : market.noPrice
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

                Section("Amount (USD)") {
                    TextField("10", text: $amount)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Button {
                        Task { await attemptTrade() }
                    } label: {
                        Text("Place order")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                } footer: {
                    Text("Trading ships in Phase 2. Peak v1 is browse-only — live prices, charts, watchlist, and read-only portfolio.")
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Coming in Phase 2")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func attemptTrade() async {
        let size = Double(amount) ?? 0
        let token = (isYes ? market.yesTokenID : market.noTokenID) ?? ""
        do {
            _ = try await env.trading.placeOrder(
                tokenID: token,
                side: .buy,
                price: price,
                size: size
            )
        } catch {
            message = error.localizedDescription
        }
    }
}
