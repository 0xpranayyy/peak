import SwiftUI

struct DepositSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment

    @State private var chain = "polygon"
    @State private var token = "USDC"
    @State private var address: String?
    @State private var message: String?
    @State private var isLoading = false

    private let chains = ["polygon", "ethereum", "base", "arbitrum", "solana"]
    private let tokens = ["USDC", "USDT", "ETH", "POL"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Chain", selection: $chain) {
                        ForEach(chains, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Token", selection: $token) {
                        ForEach(tokens, id: \.self) { Text($0).tag($0) }
                    }
                } footer: {
                    Text("Generates a Polymarket Bridge deposit address for your trading funder wallet. Send only the selected asset on that chain.")
                }

                Section {
                    Button {
                        Task { await loadAddress() }
                    } label: {
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Get deposit address")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }

                if let address {
                    Section("Deposit address") {
                        Text(address)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        ShareLink(item: address) {
                            Label("Copy / Share", systemImage: "doc.on.doc")
                        }
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadAddress() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await env.trading.requestDepositAddress(chain: chain, token: token)
            if let address = result.address, !address.isEmpty {
                self.address = address
                message = "Send \(token) on \(chain) to this address. Bridged funds credit your Polymarket funder."
            } else if let pretty = prettyJSON(result.raw) {
                address = nil
                message = pretty
            } else {
                message = "Bridge returned no address. Check proxy logs / builder settings."
            }
        } catch {
            address = nil
            message = error.localizedDescription
        }
    }

    private func prettyJSON(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}
