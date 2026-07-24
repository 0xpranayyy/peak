import SwiftUI

struct FeedItem: Identifiable, Hashable {
    let id: String
    let traderAddress: String
    let traderName: String
    let activity: PortfolioActivity
}

@MainActor
final class SocialViewModel: ObservableObject {
    enum Segment: String, CaseIterable, Identifiable {
        case feed
        case leaderboard
        case following

        var id: String { rawValue }
        var title: String {
            switch self {
            case .feed: return "Feed"
            case .leaderboard: return "Leaders"
            case .following: return "Following"
            }
        }
    }

    @Published var segment: Segment = .feed
    @Published var period: LeaderboardPeriod = .day
    @Published var leaders: [TraderSummary] = []
    @Published var feed: [FeedItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var followDraft = ""

    func loadLeaders() async {
        isLoading = true
        defer { isLoading = false }
        do {
            leaders = try await SocialAPI.fetchLeaderboard(period: period)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFeed(follows: FollowStore) async {
        guard !follows.addresses.isEmpty else {
            feed = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        var items: [FeedItem] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for address in follows.addresses.prefix(20) {
                group.addTask {
                    do {
                        let profile = try await SocialAPI.fetchProfile(address: address)
                        let rows = try await DataAPI.fetchActivity(wallet: address, limit: 8)
                        return rows.map { activity in
                            FeedItem(
                                id: "\(address)-\(activity.id)",
                                traderAddress: address,
                                traderName: profile.displayName,
                                activity: activity
                            )
                        }
                    } catch {
                        return []
                    }
                }
            }
            for await chunk in group {
                items.append(contentsOf: chunk)
            }
        }
        feed = items.sorted {
            ($0.activity.timestamp ?? .distantPast) > ($1.activity.timestamp ?? .distantPast)
        }
    }
}

struct SocialView: View {
    @EnvironmentObject private var follows: FollowStore
    @StateObject private var model = SocialViewModel()
    @State private var showAddFollow = false

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && contentIsEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage, contentIsEmpty {
                    LoadingErrorView(message: error) {
                        Task { await refresh() }
                    }
                } else {
                    listContent
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Social")
            .peakChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddFollow = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Follow wallet")
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Segment", selection: $model.segment) {
                    ForEach(SocialViewModel.Segment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(PeakMaterialBackground())
            }
            .onChange(of: model.segment) { _, _ in
                Task { await refresh() }
            }
            .onChange(of: model.period) { _, _ in
                guard model.segment == .leaderboard else { return }
                Task { await model.loadLeaders() }
            }
            .task {
                await refresh()
            }
            .refreshable {
                await refresh()
            }
            .sheet(isPresented: $showAddFollow) {
                followSheet
            }
            .navigationDestination(for: String.self) { address in
                TraderProfileView(address: address)
            }
        }
    }

    private var contentIsEmpty: Bool {
        switch model.segment {
        case .feed: return model.feed.isEmpty
        case .leaderboard: return model.leaders.isEmpty
        case .following: return follows.addresses.isEmpty
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch model.segment {
        case .feed:
            if follows.addresses.isEmpty {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "Follow traders",
                    message: "Add wallets from the leaderboard or paste an address to build your feed."
                )
            } else if model.feed.isEmpty {
                EmptyStateView(
                    systemImage: "text.bubble",
                    title: "No recent activity",
                    message: "Followed wallets haven’t traded recently."
                )
            } else {
                List {
                    ForEach(model.feed) { item in
                        NavigationLink(value: item.traderAddress) {
                            feedRow(item)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

        case .leaderboard:
            List {
                Section {
                    Picker("Period", selection: $model.period) {
                        ForEach(LeaderboardPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(model.leaders) { trader in
                        NavigationLink(value: trader.address) {
                            leaderRow(trader)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                follows.toggle(trader.address)
                            } label: {
                                Label(
                                    follows.contains(trader.address) ? "Unfollow" : "Follow",
                                    systemImage: follows.contains(trader.address) ? "person.badge.minus" : "person.badge.plus"
                                )
                            }
                            .tint(follows.contains(trader.address) ? .red : .accentColor)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

        case .following:
            if follows.addresses.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.plus",
                    title: "No follows yet",
                    message: "Follow traders from Leaders or paste a wallet address."
                )
            } else {
                List {
                    ForEach(follows.addresses, id: \.self) { address in
                        NavigationLink(value: address) {
                            HStack {
                                Image(systemName: "person.crop.circle")
                                    .foregroundStyle(.secondary)
                                Text(shorten(address))
                                    .font(.body.monospaced())
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                follows.unfollow(address)
                            } label: {
                                Label("Unfollow", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func feedRow(_ item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.traderName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(item.activity.type.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(item.activity.title)
                .font(.body)
                .lineLimit(2)
            HStack {
                if let side = item.activity.side {
                    Text("\(side.uppercased()) \(item.activity.outcome ?? "")")
                } else if let outcome = item.activity.outcome {
                    Text(outcome)
                }
                Spacer()
                if item.activity.usdcSize != 0 {
                    Text(PeakFormat.usd(item.activity.usdcSize))
                        .font(.caption.monospacedDigit())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func leaderRow(_ trader: TraderSummary) -> some View {
        HStack(spacing: 12) {
            Text(trader.rank.map { "#\($0)" } ?? "—")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(trader.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if trader.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                Text(shorten(trader.address))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if let pnl = trader.pnl {
                    Text(PeakFormat.usd(pnl, compact: true))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(pnl >= 0 ? Color.green : Color.red)
                }
                if let volume = trader.volume {
                    Text(PeakFormat.compactCurrency(volume))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var followSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0x…", text: $model.followDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .keyboardType(.asciiCapable)
                } header: {
                    Text("Wallet address")
                } footer: {
                    Text("Follow any Polymarket proxy wallet to see their trades in your feed.")
                }
            }
            .navigationTitle("Follow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddFollow = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Follow") {
                        follows.follow(model.followDraft)
                        model.followDraft = ""
                        showAddFollow = false
                        Task { await model.loadFeed(follows: follows) }
                    }
                    .disabled(!isFollowDraftValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isFollowDraftValid: Bool {
        let lower = model.followDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("0x") && lower.count == 42
    }

    private func refresh() async {
        switch model.segment {
        case .leaderboard:
            await model.loadLeaders()
        case .feed:
            await model.loadFeed(follows: follows)
        case .following:
            break
        }
    }

    private func shorten(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
