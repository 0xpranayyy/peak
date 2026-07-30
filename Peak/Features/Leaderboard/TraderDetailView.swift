import SwiftUI

/// A leaderboard trader's current open positions.
///
/// Pushed when a leaderboard row is tapped. Read-only and public — the same
/// data-api positions feed the read-only-wallet feature uses, for any address.
/// These are the trader's *current* holdings, which may differ from the
/// realized trades behind their ranking; the header says so rather than
/// implying the two are the same.
struct TraderDetailView: View {
    let entry: LeaderboardEntry
    let metric: LeaderboardAPI.Metric
    let window: LeaderboardAPI.Window

    @State private var positions: [PortfolioPosition] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        List {
            Section { header.listRowBackground(Color.clear) }

            switch phase {
            case .loading where positions.isEmpty:
                Section {
                    ForEach(0..<4, id: \.self) { _ in PeakSkeletonRow() }
                        .listRowBackground(PeakCanvas.elevated)
                }
            case .failed(let message) where positions.isEmpty:
                Section { errorRow(message).listRowBackground(PeakCanvas.elevated) }
            default:
                if positions.isEmpty {
                    Section { emptyRow.listRowBackground(PeakCanvas.elevated) }
                } else {
                    Section("Current positions") {
                        ForEach(positions) { p in
                            positionRow(p).listRowBackground(PeakCanvas.elevated)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(PeakCanvas.hairline)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(PeakMaterialBackground())
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if positions.isEmpty { await load() } }
    }

    private var header: some View {
        VStack(spacing: 10) {
            avatar
            Text(entry.displayName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text("Rank #\(entry.rank) · \(window.title) \(metric.title.lowercased()) \(amountText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var amountText: String {
        let f = PeakFormat.usd(abs(entry.amount), compact: true)
        return metric == .profit ? "\(entry.amount >= 0 ? "+" : "−")\(f)" : f
    }

    private var avatar: some View {
        Group {
            if let url = entry.profileImageURL {
                AsyncImage(url: url) { ph in
                    if case .success(let img) = ph { img.resizable().scaledToFill() } else { monogram }
                }
            } else { monogram }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(PeakCanvas.hairline, lineWidth: 1))
    }

    private var monogram: some View {
        ZStack {
            PeakCanvas.inset
            Text(entry.monogram).font(.title2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func positionRow(_ position: PortfolioPosition) -> some View {
        let pnlPositive = position.cashPnl >= 0
        let pnlColor = pnlPositive ? PeakTradeStyle.buy : PeakTradeStyle.sell
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(position.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(PeakFormat.usd(position.currentValue))
                    .font(.body.monospacedDigit().weight(.semibold))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(position.outcome)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(signedUSD(position.cashPnl))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(pnlColor)
                Text(String(format: "%+.1f%%", position.percentPnl))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(pnlColor)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            Text("Avg \(PeakFormat.cents(position.avgPrice)) · Now \(PeakFormat.cents(position.currentPrice))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(position.title), \(position.outcome), value \(PeakFormat.usd(position.currentValue)), "
            + "\(pnlPositive ? "up" : "down") \(PeakFormat.usd(abs(position.cashPnl)))"
        )
    }

    private var emptyRow: some View {
        VStack(spacing: 6) {
            Text("No open positions")
                .font(.subheadline.weight(.medium))
            Text("This trader has nothing open right now. Their ranking reflects realized trades.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func errorRow(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn’t load positions")
                .font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func signedUSD(_ value: Double) -> String {
        value > 0 ? "+\(PeakFormat.usd(value))" : PeakFormat.usd(value)
    }

    private func load() async {
        if positions.isEmpty { phase = .loading }
        do {
            // Sorted biggest-first so the trader's largest bets lead.
            let fetched = try await DataAPI.fetchPositions(wallet: entry.proxyWallet)
            positions = fetched.sorted { $0.currentValue > $1.currentValue }
            phase = .loaded
        } catch {
            phase = .failed(PeakUserCopy.fromError(error, fallback: "Couldn’t reach Polymarket. Try again."))
        }
    }
}
