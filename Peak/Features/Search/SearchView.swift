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
            errorMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t search. Try again.")
            hasSearched = true
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var recentSearches: RecentSearchStore
    @EnvironmentObject private var categoryPrefs: CategoryPreferencesStore
    @StateObject private var model = SearchViewModel()
    @State private var browseCategory: MarketCategory?
    @State private var browseEvents: [PeakEvent] = []
    @State private var isBrowsing = false

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
                        kind: .search,
                        title: "No results",
                        message: "Try a different search term, or browse Markets.",
                        actionTitle: "Browse markets"
                    ) {
                        PeakRootTab.select(.markets)
                    }
                } else {
                    resultsList
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
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

    private var idleContent: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categoryPrefs.orderedCategories) { category in
                            PeakCategoryChip(
                                title: category.title,
                                systemImage: category.systemImage,
                                selected: browseCategory == category
                            ) {
                                Task { await loadBrowse(category) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text("Browse categories")
            }

            if isBrowsing {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } else if let browseCategory, !browseEvents.isEmpty {
                Section(browseCategory.title) {
                    ForEach(browseEvents) { event in
                        NavigationLink(value: event) {
                            EventRowView(event: event)
                        }
                    }
                }
            }

            if recentSearches.queries.isEmpty && browseEvents.isEmpty && !isBrowsing {
                Section {
                    Text("Search or tap a category to explore.")
                        .foregroundStyle(.secondary)
                }
            } else if !recentSearches.queries.isEmpty {
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
        }
        .listStyle(.insetGrouped)
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
                                startDate: nil,
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

    private func loadBrowse(_ category: MarketCategory) async {
        browseCategory = category
        isBrowsing = true
        defer { isBrowsing = false }
        browseEvents = (try? await GammaAPI.fetchEvents(
            category: category,
            limit: 20,
            offset: 0,
            sort: .trending
        )) ?? []
    }
}
