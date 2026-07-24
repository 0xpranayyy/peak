import SwiftUI

@MainActor
final class TraderProfileViewModel: ObservableObject {
    @Published var profile: TraderProfile?
    @Published var positions: [PortfolioPosition] = []
    @Published var activity: [PortfolioActivity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let address: String

    init(address: String) {
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let profileTask = SocialAPI.fetchProfile(address: address)
            async let positionsTask = DataAPI.fetchPositions(wallet: address)
            async let activityTask = DataAPI.fetchActivity(wallet: address, limit: 25)
            profile = try await profileTask
            positions = (try? await positionsTask) ?? []
            activity = (try? await activityTask) ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TraderProfileView: View {
    @EnvironmentObject private var follows: FollowStore
    @StateObject private var model: TraderProfileViewModel

    init(address: String) {
        _model = StateObject(wrappedValue: TraderProfileViewModel(address: address))
    }

    var body: some View {
        Group {
            if model.isLoading && model.profile == nil {
                ProgressView("Loading profile…")
            } else if let error = model.errorMessage, model.profile == nil {
                LoadingErrorView(message: error) {
                    Task { await model.load() }
                }
            } else {
                content
            }
        }
        .navigationTitle(model.profile?.displayName ?? "Trader")
        .navigationBarTitleDisplayMode(.inline)
        .peakChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    follows.toggle(model.address)
                } label: {
                    Text(follows.contains(model.address) ? "Following" : "Follow")
                }
            }
        }
        .task {
            await model.load()
        }
        .refreshable {
            await model.load()
        }
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.profile?.displayName ?? shorten(model.address))
                        .font(.title3.weight(.bold))
                    Text(shorten(model.address))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let bio = model.profile?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let x = model.profile?.xUsername, !x.isEmpty {
                        Label("@\(x)", systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !model.positions.isEmpty {
                Section("Positions") {
                    ForEach(model.positions.prefix(12)) { position in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(position.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            HStack {
                                Text(position.outcome)
                                Spacer()
                                Text(PeakFormat.usd(position.currentValue))
                                    .font(.subheadline.monospacedDigit())
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.activity.isEmpty {
                Section("Activity") {
                    ForEach(model.activity) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Spacer()
                                Text(item.type.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                if let side = item.side {
                                    Text("\(side.uppercased()) \(item.outcome ?? "")")
                                }
                                Spacer()
                                if item.usdcSize != 0 {
                                    Text(PeakFormat.usd(item.usdcSize))
                                        .font(.caption.monospacedDigit())
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(PeakMaterialBackground())
    }

    private func shorten(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
