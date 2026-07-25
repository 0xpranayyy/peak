import SwiftUI
import UIKit

/// After sign-in: new Peak wallet vs existing Polymarket account.
struct TradingPathSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var tradingPath: TradingPathStore

    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var showImportKey = false
    @State private var showSignIn = false
    @State private var showLinkMethods = false
    @State private var profileAddress = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How do you want to trade?")
                            .font(.title2.weight(.bold))
                        Text("Pick one. You can change this later under Account.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    pathCard(
                        title: "I’m new",
                        subtitle: "Peak creates a wallet for you. Deposit, then trade.",
                        systemImage: "plus.circle"
                    ) {
                        Task { await chooseNew() }
                    }

                    pathCard(
                        title: "I already trade elsewhere",
                        subtitle: "Use the same wallet you already have.",
                        systemImage: "wallet.pass"
                    ) {
                        Task { await chooseExisting() }
                    }

                    if tradingPath.snapshot.path == .existing, showLinkMethods, !tradingPath.snapshot.imported {
                        existingLinkMethods
                    }

                    if tradingPath.snapshot.imported {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(PeakTradeStyle.buy)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(PeakUserCopy.connectedPolymarketAccount)
                                    .font(.subheadline.weight(.semibold))
                                Text(PeakUserCopy.readyToTrade)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    } else if let statusMessage {
                        Text(userFacingMessage(statusMessage))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Set up trading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isBusy)
            .sheet(isPresented: $showImportKey, onDismiss: {
                if tradingPath.snapshot.imported {
                    showLinkMethods = false
                    statusMessage = PeakUserCopy.readyToTrade
                    if tradingPath.snapshot.syncReady {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                }
            }) {
                ImportTradingWalletSheet()
                    .environmentObject(auth)
                    .environmentObject(tradingConfig)
                    .environmentObject(wallet)
                    .environmentObject(tradingPath)
            }
            .sheet(isPresented: $showSignIn) {
                PeakSignInSheet {
                    Task { await finishConnectAfterSignIn() }
                }
                .environmentObject(auth)
                .environmentObject(tradingConfig)
                .environmentObject(wallet)
            }
        }
        .presentationDetents([.medium, .large])
        .peakSheetChrome()
        .onAppear {
            // Continuing incomplete existing setup — surface Connect / Import / Paste immediately.
            if tradingPath.snapshot.imported {
                showLinkMethods = false
                return
            }
            if tradingPath.snapshot.path == .existing,
               !tradingPath.snapshot.syncReady || tradingPath.snapshot.needsImport
            {
                showLinkMethods = true
            }
        }
    }

    // MARK: - Existing path: Connect / Import / Paste

    private var existingLinkMethods: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Same wallet as Polymarket → fastest is Connect or Import key.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            linkMethodCard(
                title: "Connect wallet",
                subtitle: "MetaMask, Rainbow, Coinbase, and more",
                systemImage: "wallet.pass.fill"
            ) {
                Task { await connectWallet() }
            }

            if tradingPath.shouldOfferImport {
                linkMethodCard(
                    title: "Import private key",
                    subtitle: "Paste a key or seed to trade with that wallet",
                    systemImage: "key.fill"
                ) {
                    showImportKey = true
                }
            }

            pasteAddressCard
        }
        .padding(.top, 4)
    }

    private var pasteAddressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "doc.on.clipboard")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste address")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("View positions only — trading still needs Connect or Import key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            TextField("0x…", text: $profileAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .padding(12)
                .background(
                    PeakCanvas.inset,
                    in: RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                )
                .disabled(isBusy)

            HStack(spacing: 10) {
                Button("Paste") {
                    if let pasted = UIPasteboard.general.string {
                        profileAddress = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Button("Save") {
                    Task { await linkProfileAddress() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .disabled(isBusy || !WalletStore.isValidAddress(profileAddress))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PeakCanvas.inset,
            in: RoundedRectangle(cornerRadius: PeakLayout.cardRadius, style: .continuous)
        )
    }

    private func pathCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                PeakCanvas.inset,
                in: RoundedRectangle(cornerRadius: PeakLayout.cardRadius, style: .continuous)
            )
        }
        .peakPressable()
        .disabled(isBusy)
    }

    private func linkMethodCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                PeakCanvas.inset,
                in: RoundedRectangle(cornerRadius: PeakLayout.cardRadius, style: .continuous)
            )
        }
        .peakPressable()
        .disabled(isBusy)
    }

    private func userFacingMessage(_ raw: String) -> String {
        PeakUserCopy.sanitize(raw, fallback: "Couldn’t finish setup. Try again.")
    }

    // MARK: - Actions

    private func chooseNew() async {
        isBusy = true
        defer { isBusy = false }
        showLinkMethods = false
        tradingPath.choose(.new)
        do {
            let result = try await auth.syncTradingPath(
                .new,
                wallet: wallet,
                tradingConfig: tradingConfig,
                tradingPath: tradingPath
            )
            statusMessage = result
            if tradingPath.snapshot.syncReady {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                // Path saved but deposit wallet not ready — keep sheet open with actionable copy.
                statusMessage = result.isEmpty
                    ? "Almost there. Try again in a moment, or check Account for status."
                    : result
            }
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t finish setup. Try again.")
        }
    }

    private func chooseExisting() async {
        isBusy = true
        defer { isBusy = false }
        tradingPath.choose(.existing)
        do {
            statusMessage = try await auth.syncTradingPath(
                .existing,
                wallet: wallet,
                tradingConfig: tradingConfig,
                tradingPath: tradingPath
            )
            finishExistingPathIfReady()
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t finish setup. Try again.")
            showLinkMethods = true
        }
    }

    private func connectWallet() async {
        guard auth.isAuthenticated else {
            showSignIn = true
            return
        }
        guard WalletConnectCredentials.isConfigured else {
            #if DEBUG
            statusMessage = "Add WALLETCONNECT_PROJECT_ID from cloud.reown.com to PrivySecrets.local.plist."
            #else
            statusMessage = "Couldn’t connect. Try again later."
            #endif
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.loginWithExternalWallet()
            statusMessage = try await auth.syncTradingPath(
                .existing,
                wallet: wallet,
                tradingConfig: tradingConfig,
                tradingPath: tradingPath
            )
            finishExistingPathIfReady()
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t connect. Try again.")
            showLinkMethods = true
        }
    }

    private func finishConnectAfterSignIn() async {
        tradingPath.choose(.existing)
        isBusy = true
        defer { isBusy = false }
        do {
            statusMessage = try await auth.syncTradingPath(
                .existing,
                wallet: wallet,
                tradingConfig: tradingConfig,
                tradingPath: tradingPath
            )
            finishExistingPathIfReady()
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t finish setup. Try again.")
            showLinkMethods = true
        }
    }

    /// Existing path can be syncReady for viewing while still needing a Privy-signable import for orders.
    private func finishExistingPathIfReady() {
        if tradingPath.snapshot.imported {
            showLinkMethods = false
            if tradingPath.snapshot.syncReady {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
            return
        }
        if tradingPath.snapshot.needsImport || PeakUserCopy.isImportWalletMessage(statusMessage ?? "") {
            showLinkMethods = true
            return
        }
        if tradingPath.snapshot.syncReady {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            showLinkMethods = true
        }
    }

    private func linkProfileAddress() async {
        let trimmed = profileAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WalletStore.isValidAddress(trimmed) else { return }
        isBusy = true
        defer { isBusy = false }
        tradingPath.choose(.existing)
        wallet.save(trimmed)
        do {
            statusMessage = try await auth.syncTradingPath(
                .existing,
                wallet: wallet,
                tradingConfig: tradingConfig,
                tradingPath: tradingPath,
                accountWalletHint: trimmed
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t save that address. Try again.")
        }
    }
}
