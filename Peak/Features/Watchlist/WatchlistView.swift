import SwiftUI

@MainActor
final class WatchlistViewModel: ObservableObject {
    @Published var events: [PeakEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func reload(ids: [String]) async {
        guard !ids.isEmpty else {
            events = []
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }

        var loaded: [PeakEvent] = []
        var failures = 0
        var lastError: Error?
        for id in ids {
            do {
                let event = try await GammaAPI.fetchEvent(id: id)
                loaded.append(event)
            } catch {
                failures += 1
                lastError = error
            }
        }
        // Preserve watchlist order
        let map = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        events = ids.compactMap { map[$0] }
        if events.isEmpty && failures > 0 {
            errorMessage = PeakUserCopy.fromError(
                lastError ?? URLError(.cannotConnectToHost),
                fallback: "Couldn’t load watchlist. Try again."
            )
        } else {
            errorMessage = nil
        }
    }
}

struct WatchlistView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model = WatchlistViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if env.watchlist.eventIDs.isEmpty {
                    EmptyStateView(
                        kind: .watchlist,
                        title: "No watchlist yet",
                        message: "Star an event from Markets to keep an eye on it.",
                        actionTitle: "Browse markets"
                    ) {
                        PeakRootTab.select(.markets)
                    }
                } else if model.isLoading && model.events.isEmpty {
                    ProgressView("Loading watchlist…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage, model.events.isEmpty {
                    LoadingErrorView(message: error) {
                        Task { await model.reload(ids: env.watchlist.eventIDs) }
                    }
                } else {
                    List {
                        ForEach(model.events) { event in
                            NavigationLink(value: event) {
                                EventRowView(event: event)
                            }
                        }
                        .onDelete { indexSet in
                            let ids = indexSet.map { model.events[$0].id }
                            ids.forEach { env.watchlist.remove($0) }
                            model.events.remove(atOffsets: indexSet)
                        }
                        .onMove { from, to in
                            model.events.move(fromOffsets: from, toOffset: to)
                            env.watchlist.replaceAll(model.events.map(\.id))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .toolbar { EditButton() }
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.large)
            .peakChrome()
            .navigationDestination(for: PeakEvent.self) { event in
                EventDetailView(eventID: event.id, seed: event)
            }
            .task(id: env.watchlist.eventIDs) {
                await model.reload(ids: env.watchlist.eventIDs)
            }
            .refreshable {
                await model.reload(ids: env.watchlist.eventIDs)
                PeakHaptics.refresh()
            }
        }
    }
}
