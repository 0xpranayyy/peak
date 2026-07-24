import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var events: [PeakEvent] = []
    @Published var markets: [Market] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hasSearched = false

    private var task: Task<Void, Never>?

    func updateQuery(_ value: String) {
        query = value
        task?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            events = []
            markets = []
            hasSearched = false
            errorMessage = nil
            isSearching = false
            return
        }
        isSearching = true
        task = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    func search(_ trimmed: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let result = try await GammaAPI.search(trimmed)
            guard !Task.isCancelled else { return }
            events = result.events
            markets = result.markets
            hasSearched = true
            errorMessage = nil
        } catch is CancellationError {
            // ignore
        } catch {
            errorMessage = error.localizedDescription
            hasSearched = true
        }
    }
}

struct SearchView: View {
    @StateObject private var model = SearchViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "Search markets",
                        message: "Find events and markets on Polymarket."
                    )
                } else if model.isSearching && model.events.isEmpty && model.markets.isEmpty {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage, model.events.isEmpty && model.markets.isEmpty {
                    LoadingErrorView(message: error) {
                        Task { await model.search(model.query) }
                    }
                } else if model.hasSearched && model.events.isEmpty && model.markets.isEmpty {
                    EmptyStateView(
                        systemImage: "sparkles.slash",
                        title: "No results",
                        message: "Try a different search term."
                    )
                } else {
                    List {
                        if !model.events.isEmpty {
                            Section("Events") {
                                ForEach(model.events) { event in
                                    NavigationLink(value: event) {
                                        EventRowView(event: event)
                                    }
                                }
                            }
                        }
                        if !model.markets.isEmpty {
                            Section("Markets") {
                                ForEach(model.markets) { market in
                                    if let eventID = market.eventId {
                                        NavigationLink(value: PeakEvent(
                                            id: eventID,
                                            slug: nil,
                                            title: market.eventTitle ?? market.question,
                                            description: nil,
                                            imageURL: market.imageURL,
                                            endDate: market.endDate,
                                            volume: market.volume,
                                            volume24hr: market.volume24hr,
                                            liquidity: market.liquidity,
                                            tags: [],
                                            markets: [market]
                                        )) {
                                            MarketOutcomeBar(market: market)
                                        }
                                    } else {
                                        MarketOutcomeBar(market: market)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Search")
            .peakChrome()
            .searchable(text: $model.query, prompt: "Events, markets, topics")
            .onChange(of: model.query) { _, newValue in
                model.updateQuery(newValue)
            }
            .navigationDestination(for: PeakEvent.self) { event in
                EventDetailView(eventID: event.id, seed: event)
            }
        }
    }
}
