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

    func updateQuery(_ value: String, recent: RecentSearchStore) {
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
            await search(trimmed, recent: recent)
        }
    }

    func search(_ trimmed: String, recent: RecentSearchStore) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let result = try await GammaAPI.search(trimmed)
            guard !Task.isCancelled else { return }
            events = result.events
            markets = result.markets
            hasSearched = true
            errorMessage = nil
            if !events.isEmpty || !markets.isEmpty {
                recent.record(trimmed)
            }
        } catch is CancellationError {
            // ignore
        } catch {
            errorMessage = error.localizedDescription
            hasSearched = true
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var recentSearches: RecentSearchStore
    @StateObject private var model = SearchViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    idleContent
                } else if model.isSearching && model.events.isEmpty && model.markets.isEmpty {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage, model.events.isEmpty && model.markets.isEmpty {
                    LoadingErrorView(message: error) {
                        Task { await model.search(model.query, recent: recentSearches) }
                    }
                } else if model.hasSearched && model.events.isEmpty && model.markets.isEmpty {
                    EmptyStateView(
                        systemImage: "sparkles.slash",
                        title: "No results",
                        message: "Try a different search term."
                    )
                } else {
                    resultsList
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Search")
            .peakChrome()
            .searchable(text: $model.query, prompt: "Events, markets, topics")
            .onChange(of: model.query) { _, newValue in
                model.updateQuery(newValue, recent: recentSearches)
            }
            .navigationDestination(for: PeakEvent.self) { event in
                EventDetailView(eventID: event.id, seed: event)
            }
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        if recentSearches.queries.isEmpty {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "Search markets",
                message: "Find events and markets on Polymarket."
            )
        } else {
            List {
                Section {
                    ForEach(recentSearches.queries, id: \.self) { item in
                        Button {
                            model.query = item
                            model.updateQuery(item, recent: recentSearches)
                        } label: {
                            Label(item, systemImage: "clock")
                                .foregroundStyle(.primary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                recentSearches.remove(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Recent")
                } footer: {
                    Button("Clear Recent", role: .destructive) {
                        recentSearches.clear()
                    }
                    .font(.footnote)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var resultsList: some View {
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
