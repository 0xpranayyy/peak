import SwiftUI

/// Polymarket's public trader leaderboard, read-only.
///
/// Data is the exact board behind polymarket.com/leaderboard (lb-api), so the
/// ranking and figures match the site. Defaults to Monthly Profit — the same
/// view the official site opens on. Pushed from the Markets top bar rather
/// than given its own tab (five tabs already fill the bar; a sixth collapses
/// into iOS's "More").
struct LeaderboardView: View {
    @Environment(\.peakBrand) private var brand

    @State private var metric: LeaderboardAPI.Metric = .profit
    @State private var window: LeaderboardAPI.Window = .month
    @State private var entries: [LeaderboardEntry] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            content
        }
        .background(PeakMaterialBackground())
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        // Re-runs whenever the metric or window changes, and on first appear.
        .task(id: "\(metric.rawValue)-\(window.rawValue)") { await load() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Metric", selection: $metric) {
                ForEach(LeaderboardAPI.Metric.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Picker("Window", selection: $window) {
                ForEach(LeaderboardAPI.Window.allCases) { w in
                    Text(w.title).tag(w)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading where entries.isEmpty:
            PeakSkeletonList(style: .markets, rowCount: 10)
        case .failed(let message) where entries.isEmpty:
            errorState(message)
        default:
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    NavigationLink {
                        TraderDetailView(entry: entry, metric: metric, window: window)
                    } label: {
                        LeaderboardRow(entry: entry, metric: metric)
                    }
                    .listRowBackground(PeakCanvas.elevated)
                }
            } footer: {
                Text("Live from Polymarket. Peak is an independent client and doesn’t rank or verify traders itself.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(PeakCanvas.hairline)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .refreshable { await load() }
        // Dim slightly while a toggle change is loading fresh rows.
        .opacity(phase == .loading ? 0.5 : 1)
        .animation(PeakMotion.soft, value: phase == .loading)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            PeakEmptyVisual(kind: .markets, size: 72)
            Text("Couldn’t load the leaderboard")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(brand.mid)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func load() async {
        if entries.isEmpty { phase = .loading }
        do {
            let fetched = try await LeaderboardAPI.fetch(metric: metric, window: window)
            entries = fetched
            phase = .loaded
        } catch {
            phase = .failed(PeakUserCopy.fromError(error, fallback: "Couldn’t reach Polymarket. Check your connection and try again."))
        }
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let metric: LeaderboardAPI.Metric

    private var isProfit: Bool { metric == .profit }
    private var isPositive: Bool { entry.amount >= 0 }

    var body: some View {
        HStack(spacing: 12) {
            rankBadge

            avatar

            Text(entry.displayName)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(amountText)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rank \(entry.rank), \(entry.displayName), "
            + "\(metric.title.lowercased()) \(amountText)"
        )
    }

    private var amountText: String {
        let formatted = PeakFormat.usd(abs(entry.amount), compact: true)
        if isProfit { return "\(isPositive ? "+" : "−")\(formatted)" }
        return formatted
    }

    private var amountColor: Color {
        guard isProfit else { return .primary }
        return isPositive ? PeakTradeStyle.buy : PeakTradeStyle.sell
    }

    /// Top three get a medal tint; the rest a plain muted number.
    private var rankBadge: some View {
        Text("\(entry.rank)")
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(medalColor ?? .secondary)
            .frame(minWidth: 28, alignment: .center)
    }

    private var medalColor: Color? {
        switch entry.rank {
        case 1: return Color(red: 0.85, green: 0.68, blue: 0.28) // gold
        case 2: return Color(red: 0.66, green: 0.70, blue: 0.74) // silver
        case 3: return Color(red: 0.78, green: 0.53, blue: 0.33) // bronze
        default: return nil
        }
    }

    private var avatar: some View {
        Group {
            if let url = entry.profileImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(PeakCanvas.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        ZStack {
            PeakCanvas.inset
            Text(entry.monogram)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
