import SwiftUI

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
    @State private var showMoreOptions = false
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

                    if tradingPath.snapshot.path == .existing {
                        existingExtras
                    }

                    if let statusMessage {
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
            .sheet(isPresented: $showImportKey) {
                ImportTradingWalletSheet()
                    .environmentObject(auth)
                    .environmentObject(tradingConfig)
                    .environmentObject(wallet)
                    .environmentObject(tradingPath)
            }
        }
        .presentationDetents([.medium, .large])
        .peakSheetChrome()
    }

    private var existingExtras: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("If your wallet didn’t link automatically, use an option below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("More options", isExpanded: $showMoreOptions) {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        showImportKey = true
                    } label: {
                        Label("Import wallet", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    Text("Or paste a profile address to view positions (trading still needs a connected wallet).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("0x…", text: $profileAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding(12)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                        )

                    Button("Save address") {
                        Task { await linkProfileAddress() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy || !WalletStore.isValidAddress(profileAddress))
                }
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(.top, 4)
        .onAppear {
            if statusMessage != nil || !(tradingPath.snapshot.syncReady) {
                showMoreOptions = true
            }
        }
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
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: PeakLayout.cardRadius, style: .continuous)
            )
        }
        .peakPressable()
        .disabled(isBusy)
    }

    private func userFacingMessage(_ raw: String) -> String {
        PeakUserCopy.sanitize(raw, fallback: "Couldn’t finish setup. Try again.")
    }

    private func chooseNew() async {
        isBusy = true
        defer { isBusy = false }
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
            if tradingPath.snapshot.syncReady {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                showMoreOptions = true
            }
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t finish setup. Try again.")
            showMoreOptions = true
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
