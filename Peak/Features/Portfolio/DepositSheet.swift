import SwiftUI
import UIKit

struct DepositSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment

    @State private var chain = "polygon"
    @State private var token = "USDC"
    @State private var address: String?
    @State private var message: String?
    @State private var isLoading = false
    @State private var didCopyAddress = false
    @State private var confirmedSend = false
    @State private var waitingForFunds = false

    private let chains = ["polygon", "ethereum", "base", "arbitrum", "solana"]
    private let tokens = ["USDC", "USDT", "ETH", "POL"]

    private var confirmLabel: String {
        "I will send \(token) on \(chain.capitalized)"
    }

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
                    Text("We’ll create a deposit address for your trading wallet. Send only \(token) on \(chain.capitalized). Wrong network or asset can mean permanent loss of funds.")
                }

                Section {
                    Button {
                        Task { await loadAddress() }
                    } label: {
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(address == nil ? "Get deposit address" : "Refresh deposit address")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .controlSize(.large)
                    .disabled(isLoading)
                    .frame(minHeight: 44)
                }

                if let address {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Confirm before you send", systemImage: "checkmark.shield")
                                .font(.subheadline.weight(.semibold))
                            confirmRow(title: "Token", value: token)
                            confirmRow(title: "Chain", value: chain.capitalized)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Address")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(address)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(nil)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel("Deposit address")
                                    .accessibilityValue(address)
                            }
                        }
                        .padding(.vertical, 4)

                        Toggle(isOn: $confirmedSend) {
                            Text(confirmLabel)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(PeakTradeStyle.buy)
                        .accessibilityLabel(confirmLabel)
                    } header: {
                        Text("Verify destination")
                    } footer: {
                        Text("Wrong network or asset = loss of funds. Double-check token, chain, and the full address before sending.")
                    }

                    Section {
                        depositQRBlock(for: address)
                            .opacity(confirmedSend ? 1 : 0.45)
                            .allowsHitTesting(confirmedSend)

                        HStack(spacing: 12) {
                            Button {
                                copyFullAddress(address)
                            } label: {
                                Label(didCopyAddress ? "Copied" : "Copy address", systemImage: didCopyAddress ? "checkmark" : "doc.on.doc")
                                    .frame(minHeight: 44)
                            }
                            .disabled(!confirmedSend || didCopyAddress)

                            ShareLink(item: address) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .frame(minHeight: 44)
                            }
                            .disabled(!confirmedSend)
                            .accessibilityLabel("Share deposit address")
                            .simultaneousGesture(TapGesture().onEnded {
                                guard confirmedSend else { return }
                                waitingForFunds = true
                                message = nil
                            })
                        }
                    } header: {
                        Text("Copy or scan")
                    } footer: {
                        if confirmedSend {
                            Text("Scan or copy the full address. Send only \(token) on \(chain.capitalized).")
                        } else {
                            Text("Confirm \(token) on \(chain.capitalized) above to unlock copy and QR.")
                        }
                    }
                }

                if waitingForFunds {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Waiting for funds", systemImage: "clock")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PeakTradeStyle.buy)
                            Text("Funds usually arrive shortly after you send. Pull to refresh Portfolio when ready.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                } else if let message {
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
            .onChange(of: chain) { _, _ in clearDepositResult() }
            .onChange(of: token) { _, _ in clearDepositResult() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func confirmRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    @ViewBuilder
    private func depositQRBlock(for address: String) -> some View {
        VStack(spacing: 12) {
            if let qr = PeakQRCode.image(from: address) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityLabel("QR code for deposit address")
                    .accessibilityHint("Encodes the full deposit address. Send only \(token) on \(chain.capitalized).")
                    .accessibilityHidden(!confirmedSend)
            }

            Text("\(token) · \(chain.capitalized)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Wrong network or asset = loss of funds")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PeakTradeStyle.sell)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func copyFullAddress(_ address: String) {
        UIPasteboard.general.string = address
        PeakHaptics.selection()
        didCopyAddress = true
        waitingForFunds = true
        message = nil
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            didCopyAddress = false
        }
    }

    private func clearDepositResult() {
        address = nil
        message = nil
        didCopyAddress = false
        confirmedSend = false
        waitingForFunds = false
    }

    private func loadAddress() async {
        isLoading = true
        defer { isLoading = false }
        didCopyAddress = false
        confirmedSend = false
        waitingForFunds = false
        do {
            let result = try await env.trading.requestDepositAddress(chain: chain, token: token)
            if let address = result.address, !address.isEmpty {
                self.address = address
                message = "Confirm \(token) on \(chain.capitalized), then copy or scan the full address."
            } else if let pretty = prettyJSON(result.raw) {
                address = nil
                #if DEBUG
                message = pretty
                #else
                message = "Couldn’t get a deposit address. Try again."
                #endif
            } else {
                message = "Couldn’t get a deposit address. Try again."
            }
        } catch {
            address = nil
            message = PeakUserCopy.fromError(error, fallback: "Couldn’t get a deposit address. Try again.")
        }
    }

    private func prettyJSON(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}
