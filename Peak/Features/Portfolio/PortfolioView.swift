import SwiftUI

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published var positions: [PortfolioPosition] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var draftAddress = ""

    var totalValue: Double {
        positions.reduce(0) { $0 + $1.currentValue }
    }

    var totalPnl: Double {
        positions.reduce(0) { $0 + $1.cashPnl }
    }

    func syncDraft(from wallet: WalletStore) {
        if draftAddress.isEmpty {
            draftAddress = wallet.address ?? ""
        }
    }

    func load(wallet: WalletStore) async {
        guard wallet.isValid, let address = wallet.address else {
            positions = []
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            positions = try await DataAPI.fetchPositions(wallet: address)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PortfolioView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model = PortfolioViewModel()
    @State private var showWalletEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if !env.wallet.isValid {
                    walletPrompt
                } else if model.isLoading && model.positions.isEmpty {
                    ProgressView("Loading positions…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage, model.positions.isEmpty {
                    LoadingErrorView(message: error) {
                        Task { await model.load(wallet: env.wallet) }
                    }
                } else if model.positions.isEmpty {
                    EmptyStateView(
                        systemImage: "briefcase",
                        title: "No open positions",
                        message: "This wallet has no positions on Polymarket right now."
                    )
                } else {
                    positionsList
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Portfolio")
            .peakChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            .task(id: env.wallet.address) {
                model.syncDraft(from: env.wallet)
                await model.load(wallet: env.wallet)
            }
            .refreshable {
                await model.load(wallet: env.wallet)
            }
        }
    }

    private var walletPrompt: some View {
        ContentUnavailableView {
            Label("Add a wallet", systemImage: "wallet.pass")
        } description: {
            Text("Peak shows a read-only Polymarket portfolio for any wallet address. Nothing is signed or stored beyond the address.")
        } actions: {
            Button("Add Wallet") {
                model.draftAddress = ""
                showWalletEditor = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var positionsList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Portfolio value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(PeakFormat.usd(model.totalValue))
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                    Text("PnL \(PeakFormat.usd(model.totalPnl))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(model.totalPnl >= 0 ? Color.green : Color.red)
                    if let address = env.wallet.address {
                        Text(shorten(address))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

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
                    Text("Stored securely in Keychain on this device. Peak never places orders.")
                }

                if env.wallet.address != nil {
                    Section {
                        Button("Remove wallet", role: .destructive) {
                            env.wallet.clear()
                            model.draftAddress = ""
                            model.positions = []
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
