import SwiftUI
import UIKit

struct DepositSheet: View {
    @Environment(\.peakBrand) private var brand
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingPath: TradingPathStore
    @EnvironmentObject private var tradingConfig: TradingConfigStore

    @State private var chain = "polygon"
    @State private var token = "USDC"
    @State private var address: String?
    @State private var message: String?
    @State private var isLoading = false
    @State private var didCopyAddress = false
    @State private var confirmedSend = false
    @State private var waitingForFunds = false
    @State private var needsSetup = false

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
                        Task { await loadAddress(forceSetup: needsSetup) }
                    } label: {
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(buttonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(brand.mid)
                    .controlSize(.large)
                    .disabled(isLoading || !auth.isAuthenticated)
                    .frame(minHeight: 44)
                } footer: {
                    if !auth.isAuthenticated {
                        Text("Sign in under Account first.")
                    } else if needsSetup {
                        Text("Trading setup isn’t finished yet. Tap above to finish, then get an address.")
                    }
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

                        if confirmedSend {
                            Label(confirmLabel, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(PeakTradeStyle.buy)
                                .accessibilityLabel(confirmLabel)
                        } else {
                            Button {
                                confirmedSend = true
                                PeakHaptics.selection()
                            } label: {
                                Text(confirmLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(PeakTradeStyle.buy)
                            .accessibilityLabel(confirmLabel)
                        }
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
                            Text("Tap “\(confirmLabel)” above to unlock copy and QR.")
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
                            .foregroundStyle(needsSetup ? PeakTradeStyle.sell : .secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PeakMaterialBackground())
            .navigationTitle("Deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: chain) { _, _ in clearDepositResult() }
            .onChange(of: token) { _, _ in clearDepositResult() }
            .task {
                tradingConfig.ensureBackendURLIfNeeded()
                needsSetup = !tradingPath.snapshot.syncReady
                    || tradingPath.snapshot.accountWallet == nil
                if auth.isAuthenticated {
                    await loadAddress(forceSetup: needsSetup)
                }
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .peakSheetChrome()
    }

    private var buttonTitle: String {
        if needsSetup { return "Finish setup & get address" }
        if address == nil { return "Get deposit address" }
        return "Refresh deposit address"
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
                    .clipShape(RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
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

    @MainActor
    private func loadAddress(forceSetup: Bool) async {
        guard auth.isAuthenticated else {
            message = "Sign in under Account first."
            return
        }

        isLoading = true
        defer { isLoading = false }
        didCopyAddress = false
        confirmedSend = false
        waitingForFunds = false
        tradingConfig.ensureBackendURLIfNeeded()

        do {
            if forceSetup || !tradingPath.snapshot.syncReady || tradingPath.snapshot.accountWallet == nil {
                message = "Finishing trading setup…"
                try await ensureTradingReady()
            }

            let result = try await env.trading.requestDepositAddress(chain: chain, token: token)
            if let resolved = result.address, !resolved.isEmpty {
                applyAddress(resolved, note: result.raw["note"] as? String)
                return
            }

            if let fallback = localFallbackAddress() {
                applyAddress(
                    fallback,
                    note: "Showing your trading wallet for \(chain.capitalized) deposits."
                )
                return
            }

            address = nil
            needsSetup = true
            message = "Couldn’t get a deposit address. Finish Set up trading under Account, then try again."
        } catch let error as TradingError {
            await handleDepositError(error)
        } catch {
            if let trading = error as? TradingError {
                await handleDepositError(trading)
            } else if let http = error as? TradingProxyClient.HTTPBodyError {
                tradingPath.apply(server: http.body)
                await handleDepositError(http.tradingError)
            } else {
                // Network / DNS failures — still offer local wallet when we have one.
                if let fallback = localFallbackAddress(), chain.lowercased() == "polygon" {
                    applyAddress(
                        fallback,
                        note: "Couldn’t reach Peak servers. Showing your trading wallet for same-chain Polygon deposits."
                    )
                    return
                }
                address = nil
                message = PeakUserCopy.fromError(error, fallback: "Couldn’t get a deposit address. Check your connection and try again.")
            }
        }
    }

    @MainActor
    private func ensureTradingReady() async throws {
        guard let path = tradingPath.snapshot.path else {
            needsSetup = true
            throw TradingError.setupRequired
        }
        let eoa = auth.walletAddress ?? env.wallet.address
        guard let eoa, tradingConfig.hasBackendURL else {
            throw TradingError.notConfigured
        }

        let session = try await TradingProxyClient.syncPrivySession(
            eoa: eoa,
            path: path.rawValue,
            accountWallet: tradingPath.snapshot.accountWallet
        )
        tradingPath.apply(server: session)

        if tradingPath.snapshot.syncReady, tradingPath.snapshot.accountWallet != nil {
            needsSetup = false
            return
        }

        do {
            let setup = try await TradingProxyClient.setupTrading()
            tradingPath.apply(server: setup)
            if let account = setup["accountWallet"] as? String, WalletStore.isValidAddress(account) {
                env.wallet.save(account)
            }
            needsSetup = !(tradingPath.snapshot.syncReady && tradingPath.snapshot.accountWallet != nil)
        } catch let http as TradingProxyClient.HTTPBodyError {
            tradingPath.apply(server: http.body)
            if let account = http.body["accountWallet"] as? String, WalletStore.isValidAddress(account) {
                env.wallet.save(account)
            }
            // If we still have a wallet, continue to deposit-address; otherwise surface setup error.
            if tradingPath.snapshot.accountWallet == nil {
                needsSetup = true
                throw http.tradingError
            }
            needsSetup = false
        }
    }

    @MainActor
    private func handleDepositError(_ error: TradingError) async {
        switch error {
        case .setupRequired, .builderNotReady:
            // One automatic setup retry, then surface.
            if !needsSetup {
                needsSetup = true
                do {
                    try await ensureTradingReady()
                    let result = try await env.trading.requestDepositAddress(chain: chain, token: token)
                    if let resolved = result.address, !resolved.isEmpty {
                        applyAddress(resolved, note: result.raw["note"] as? String)
                        return
                    }
                } catch {
                    // fall through
                }
            }
            if let fallback = localFallbackAddress() {
                applyAddress(
                    fallback,
                    note: "Setup still finishing — showing your trading wallet for \(chain.capitalized)."
                )
                return
            }
            address = nil
            needsSetup = true
            message = error.errorDescription ?? TradingError.setupRequired.errorDescription
        case .notConfigured:
            address = nil
            message = "Sign in under Account, then try again."
        default:
            if let fallback = localFallbackAddress(), chain.lowercased() == "polygon" {
                applyAddress(
                    fallback,
                    note: "\(error.errorDescription ?? "Couldn’t refresh bridge address.") Showing your trading wallet for Polygon."
                )
                return
            }
            address = nil
            message = PeakUserCopy.fromError(error, fallback: "Couldn’t get a deposit address. Try again.")
        }
    }

    private func localFallbackAddress() -> String? {
        if let account = tradingPath.snapshot.accountWallet, WalletStore.isValidAddress(account) {
            return account
        }
        if let funder = env.wallet.address, WalletStore.isValidAddress(funder) {
            return funder
        }
        if let eoa = auth.walletAddress, WalletStore.isValidAddress(eoa) {
            return eoa
        }
        return nil
    }

    private func applyAddress(_ value: String, note: String?) {
        address = value
        needsSetup = false
        if let note, !note.isEmpty {
            message = note
        } else {
            message = "Confirm \(token) on \(chain.capitalized), then copy or scan the full address."
        }
    }
}
