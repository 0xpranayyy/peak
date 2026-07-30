import SwiftUI

/// Polymarket's public trader leaderboard, read-only.
///
/// Pushed from the Markets top bar rather than given its own tab — five tabs
/// already fill the bar, and a sixth would collapse the lot into iOS's "More"
/// list. Deliberately a lean list: this mirrors Polymarket's own ranking, it
/// isn't a social surface (no following, no profiles to open).
struct LeaderboardView: View {
    @Environment(\.peakBrand) private var brand

    @State private var entries: [LeaderboardEntry] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading where entries.isEmpty:
                PeakSkeletonList(style: .markets, rowCount: 10)
            case .failed(let message) where entries.isEmpty:
                errorState(message)
            default:
                list
            }
        }
        .background(PeakMaterialBackground())
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if entries.isEmpty { await load() }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    LeaderboardRow(entry: entry)
                        .listRowBackground(PeakCanvas.elevated)
                }
            } header: {
                Text("Top traders on Polymarket, by all-time profit")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            } footer: {
                Text("Live from Polymarket. Peak is an independent client and doesn’t rank or verify traders itself.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(PeakCanvas.hairline)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .refreshable { await load() }
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
            Button("Try again") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(brand.mid)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func load() async {
        if entries.isEmpty { phase = .loading }
        do {
            let fetched = try await LeaderboardAPI.fetch(limit: 100)
            entries = fetched
            phase = .loaded
        } catch {
            phase = .failed(PeakUserCopy.fromError(error, fallback: "Couldn’t reach Polymarket. Check your connection and try again."))
        }
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry

    private var isPositive: Bool { entry.pnl >= 0 }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .trailing)

            avatar

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if entry.verifiedBadge {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(PeakTradeStyle.buy)
                            .accessibilityLabel("Verified")
                    }
                }
                Text("Volume \(PeakFormat.usd(entry.vol, compact: true))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(isPositive ? "+" : "")\(PeakFormat.usd(entry.pnl, compact: true))")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(isPositive ? PeakTradeStyle.buy : PeakTradeStyle.sell)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rank \(entry.rank), \(entry.displayName)\(entry.verifiedBadge ? ", verified" : ""), "
            + "profit \(isPositive ? "up" : "down") \(PeakFormat.usd(abs(entry.pnl), compact: true)), "
            + "volume \(PeakFormat.usd(entry.vol, compact: true))"
        )
    }

    private var avatar: some View {
        Group {
            if let url = entry.profileImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: 34, height: 34)
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
