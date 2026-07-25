import SwiftUI

@MainActor
final class MarketsViewModel: ObservableObject {
    @Published var events: [PeakEvent] = []
    @Published var selectedCategory: MarketCategory?
    @Published var sort: MarketSort = .trending
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var canLoadMore = true
    /// CLOB display odds per event id (mid unless spread > 10¢ → Gamma last/outcome).
    @Published var displayOdds: [String: Double] = [:]

    private let pageSize = 24
    private var offset = 0
    private var loadTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var oddsTask: Task<Void, Never>?
    private var didWarmRelated = false

    private var cacheKey: String {
        MarketsCache.key(sort: sort, categorySlug: selectedCategory?.slug)
    }

    func onAppear() {
        Task { await bootstrap() }
    }

    func selectCategory(_ category: MarketCategory?) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        Task { await switchFeed() }
    }

    func selectSort(_ sort: MarketSort) {
        guard self.sort != sort else { return }
        self.sort = sort
        Task { await switchFeed() }
    }

    func bootstrap() async {
        if events.isEmpty {
            await hydrateFromCache()
        }
        if events.isEmpty {
            isLoading = true
        }
        await refresh(reset: true, userInitiated: false)
        warmRelatedCategories()
    }

    private func switchFeed() async {
        loadTask?.cancel()
        prefetchTask?.cancel()
        oddsTask?.cancel()
        offset = 0
        canLoadMore = true
        errorMessage = nil
        displayOdds = [:]

        if let page = await MarketsCache.shared.page(for: cacheKey), !page.events.isEmpty {
            events = page.events
            offset = page.canLoadMore ? pageSize : page.events.count
            canLoadMore = page.canLoadMore
            isLoading = false
            isRefreshing = true
        } else {
            events = []
            isLoading = true
            isRefreshing = false
        }

        await refresh(reset: true, userInitiated: false)
    }

    func refresh(reset: Bool, userInitiated: Bool) async {
        loadTask?.cancel()

        if reset {
            offset = 0
            canLoadMore = true
            errorMessage = nil
            if !userInitiated {
                await hydrateFromCache()
            }
            if events.isEmpty {
                isLoading = true
            } else {
                isRefreshing = true
            }
        } else {
            guard canLoadMore, !isLoadingMore, !isLoading else { return }
            isLoadingMore = true
        }

        let currentOffset = offset
        let sort = self.sort
        let category = selectedCategory
        let key = cacheKey
        let forceFresh = userInitiated && reset

        loadTask = Task {
            do {
                let page: (events: [PeakEvent], canLoadMore: Bool)
                if let category {
                    page = try await GammaAPI.fetchEventsPage(
                        category: category,
                        limit: pageSize,
                        offset: currentOffset,
                        sort: sort,
                        forceFresh: forceFresh
                    )
                } else {
                    page = try await GammaAPI.fetchEventsPage(
                        limit: pageSize,
                        offset: currentOffset,
                        sort: sort,
                        tagSlug: nil,
                        forceFresh: forceFresh
                    )
                }
                guard !Task.isCancelled else { return }

                if reset {
                    events = page.events
                    offset = currentOffset + pageSize
                    // Prefer server page fullness so dropping a few stale rows doesn't stall pagination.
                    canLoadMore = page.canLoadMore
                    await MarketsCache.shared.store(page.events, canLoadMore: canLoadMore, for: key)
                    prefetchNextPageIfNeeded()
                    enrichDisplayOdds(for: page.events, replace: true)
                } else {
                    let existing = Set(events.map(\.id))
                    let fresh = page.events.filter { !existing.contains($0.id) }
                    events.append(contentsOf: fresh)
                    offset = currentOffset + pageSize
                    canLoadMore = page.canLoadMore
                    enrichDisplayOdds(for: fresh, replace: false)
                }
                errorMessage = nil
            } catch is CancellationError {
                // ignore
            } catch {
                if reset && events.isEmpty {
                    errorMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t load markets. Try again.")
                }
            }
            isLoading = false
            isRefreshing = false
            isLoadingMore = false
        }
        await loadTask?.value
    }

    func loadMoreIfNeeded(current event: PeakEvent) async {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        if idx >= events.count - 6 {
            await refresh(reset: false, userInitiated: false)
        }
    }

    private func hydrateFromCache() async {
        let key = cacheKey
        if let page = await MarketsCache.shared.page(for: key), !page.events.isEmpty {
            events = page.events
            offset = page.canLoadMore ? pageSize : page.events.count
            canLoadMore = page.canLoadMore
            isLoading = false
        }
    }

    private func prefetchNextPageIfNeeded() {
        guard canLoadMore else { return }
        prefetchTask?.cancel()
        let nextOffset = offset
        let sort = self.sort
        let category = selectedCategory
        prefetchTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            do {
                let page: (events: [PeakEvent], canLoadMore: Bool)
                if let category {
                    page = try await GammaAPI.fetchEventsPage(
                        category: category,
                        limit: pageSize,
                        offset: nextOffset,
                        sort: sort
                    )
                } else {
                    page = try await GammaAPI.fetchEventsPage(
                        limit: pageSize,
                        offset: nextOffset,
                        sort: sort
                    )
                }
                guard !Task.isCancelled, !page.events.isEmpty else { return }
                await MainActor.run {
                    guard self.offset == nextOffset, self.canLoadMore else { return }
                    let existing = Set(self.events.map(\.id))
                    let fresh = page.events.filter { !existing.contains($0.id) }
                    self.events.append(contentsOf: fresh)
                    self.offset = nextOffset + self.pageSize
                    self.canLoadMore = page.canLoadMore
                }
            } catch {
                // Prefetch failures are silent.
            }
        }
    }

    private func warmRelatedCategories() {
        guard !didWarmRelated else { return }
        didWarmRelated = true
        let interests = CategoryPreferencesStore.shared.interestedCategories.prefix(3)
        Task(priority: .background) {
            await MarketsCache.shared.warmTrending()
            for category in interests {
                let key = MarketsCache.key(sort: .trending, categorySlug: category.slug)
                if let existing = await MarketsCache.shared.page(for: key), existing.isFresh {
                    continue
                }
                if let page = try? await GammaAPI.fetchEventsPage(
                    category: category,
                    limit: pageSize,
                    offset: 0,
                    sort: .trending
                ), !page.events.isEmpty {
                    await MarketsCache.shared.store(page.events, canLoadMore: page.canLoadMore, for: key)
                }
            }
        }
    }

    /// Refresh list badges from CLOB mid/spread (same rule as event detail).
    /// Merges into `displayOdds` without replacing dictionary identity on each tick.
    private func enrichDisplayOdds(for page: [PeakEvent], replace: Bool) {
        oddsTask?.cancel()
        let targets: [(eventID: String, tokenID: String, fallback: Double)] = page.compactMap { event in
            guard let market = event.primaryMarket,
                  let token = market.yesTokenID, !token.isEmpty else { return nil }
            return (event.id, token, market.yesPrice)
        }
        if replace, targets.isEmpty {
            displayOdds = [:]
            return
        }
        guard !targets.isEmpty else { return }

        oddsTask = Task(priority: .utility) {
            var updates: [String: Double] = [:]
            await withTaskGroup(of: (String, Double).self) { group in
                for target in targets {
                    group.addTask {
                        let m = try? await CLOBAPI.fetchMidpoint(tokenID: target.tokenID)
                        let s = try? await CLOBAPI.fetchSpread(tokenID: target.tokenID)
                        let value = PeakTradeStyle.displayedOdds(
                            mid: m,
                            spread: s,
                            lastTrade: target.fallback,
                            fallback: target.fallback
                        )
                        return (target.eventID, value)
                    }
                }
                for await item in group {
                    updates[item.0] = item.1
                }
            }
            guard !Task.isCancelled else { return }
            // Coalesce UI publish onto MainActor in one merge pass.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let keepIDs = Set(page.map(\.id))
            await MainActor.run {
                if replace {
                    var next = displayOdds.filter { keepIDs.contains($0.key) }
                    next.merge(updates) { _, new in new }
                    displayOdds = next
                } else {
                    displayOdds.merge(updates) { _, new in new }
                }
            }
        }
    }
}

struct MarketsView: View {
    @EnvironmentObject private var categoryPrefs: CategoryPreferencesStore
    @EnvironmentObject private var digest: DailyDigestStore
    @StateObject private var model = MarketsViewModel()
    @State private var shareEvent: PeakEvent?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.isLoading && model.events.isEmpty {
                    skeletonList
                } else if let error = model.errorMessage, model.events.isEmpty {
                    LoadingErrorView(message: error) {
                        Task { await model.refresh(reset: true, userInitiated: true) }
                    }
                } else {
                    listContent
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Markets")
            .navigationBarTitleDisplayMode(.large)
            .peakChrome()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CompareMarketsView()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .accessibilityLabel("Compare markets")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        if model.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Menu {
                            ForEach(MarketSort.allCases) { sort in
                                Button {
                                    model.selectSort(sort)
                                } label: {
                                    HStack {
                                        Text(sort.title)
                                        if model.sort == sort {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(model.sort.title, systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .refreshable {
                await model.refresh(reset: true, userInitiated: true)
                await digest.refreshMovers(interests: categoryPrefs.interestedCategories)
                PeakHaptics.refresh()
            }
            .onAppear { model.onAppear() }
            .task {
                await digest.refreshMovers(interests: categoryPrefs.interestedCategories)
            }
        }
    }

    private var listContent: some View {
        List {
            if digest.showBanner, !digest.movers.isEmpty {
                Section {
                    ForYouRailView(
                        events: digest.movers,
                        title: "Morning digest",
                        subtitle: "Top movers in your categories",
                        onSelect: { path.append($0) },
                        onDismiss: { digest.dismissBanner() }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }
            } else if !digest.movers.isEmpty {
                Section {
                    ForYouRailView(
                        events: Array(digest.movers.prefix(6)),
                        title: "For you",
                        subtitle: categoryPrefs.interestedCategories.isEmpty
                            ? "Trending across Peak"
                            : "Pinned to your interests",
                        onSelect: { path.append($0) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }
            } else if !model.isLoading {
                Section {
                    marketsHeroFallback
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            categoryStrip

            Section {
                if model.events.isEmpty, !model.isLoading, !model.isRefreshing {
                    VStack(spacing: 14) {
                        PeakEmptyVisual(kind: .markets, size: 72)
                        Text("Nothing open here")
                            .font(.headline)
                        Text(
                            model.selectedCategory == nil
                                ? "Pull to refresh, or try another sort."
                                : "Try another category, or see everything."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        if model.selectedCategory != nil {
                            Button("Browse all markets") {
                                model.selectCategory(nil)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentColor)
                            .controlSize(.large)
                            .frame(minHeight: 44)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(Array(model.events.enumerated()), id: \.element.id) { index, event in
                    NavigationLink(value: event) {
                        EventRowView(
                            event: event,
                            displayedProbability: model.displayOdds[event.id]
                        )
                    }
                    .modifier(MarketsRowAppear(index: index))
                    .contextMenu {
                        Button {
                            shareEvent = event
                        } label: {
                            Label("Share card", systemImage: "square.and.arrow.up")
                        }
                    }
                    .task {
                        await model.loadMoreIfNeeded(current: event)
                    }
                }

                if model.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                marketsSectionHeader
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: PeakEvent.self) { event in
            EventDetailView(eventID: event.id, seed: event)
        }
        .sheet(item: $shareEvent) { event in
            ShareMarketSheet(event: event, market: event.primaryMarket)
        }
    }

    private var marketsHeroFallback: some View {
        HStack(alignment: .center, spacing: 12) {
            PeakAppLogo(size: 32, showGlow: false)
            VStack(alignment: .leading, spacing: 3) {
                Text("Markets")
                    .font(.title3.weight(.bold))
                Text(model.sort.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .peakAppear()
    }

    @ViewBuilder
    private var marketsSectionHeader: some View {
        if let selected = model.selectedCategory {
            Text("\(selected.title) · \(model.sort.title)")
        } else if !categoryPrefs.interestedCategories.isEmpty {
            Text("For you · \(model.sort.title)")
        } else {
            Text(model.sort.title)
        }
    }

    private var skeletonList: some View {
        List {
            Section {
                HStack(alignment: .center, spacing: 12) {
                    PeakSkeleton(height: 32, width: 32, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 6) {
                        PeakSkeleton(height: 16, width: 100, cornerRadius: 5)
                        PeakSkeleton(height: 10, width: 140, cornerRadius: 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            categoryStrip
            Section {
                ForEach(0..<8, id: \.self) { _ in
                    PeakSkeletonRow()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading markets")
    }

    private var categoryStrip: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PeakCategoryChip(title: "All", selected: model.selectedCategory == nil) {
                        model.selectCategory(nil)
                    }
                    ForEach(categoryPrefs.orderedCategories) { category in
                        PeakCategoryChip(
                            title: category.title,
                            systemImage: category.systemImage,
                            selected: model.selectedCategory == category
                        ) {
                            model.selectCategory(category)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }
}

/// Appear animation only for the first screenful of rows (avoids List recycle jank).
private struct MarketsRowAppear: ViewModifier {
    let index: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if index < PeakMotion.appearRowCap {
            content.peakAppear(delay: PeakMotion.staggerDelay(index: index))
        } else {
            content
        }
    }
}
