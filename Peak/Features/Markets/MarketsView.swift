import SwiftUI

@MainActor
final class MarketsViewModel: ObservableObject {
    @Published var events: [PeakEvent] = []
    @Published var tags: [MarketTag] = []
    @Published var selectedTag: MarketTag?
    @Published var sort: MarketSort = .trending
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var canLoadMore = true

    private let pageSize = 20
    private var offset = 0
    private var loadTask: Task<Void, Never>?

    func onAppear() {
        if events.isEmpty {
            Task { await refresh(reset: true) }
        }
        if tags.isEmpty {
            Task { await loadTags() }
        }
    }

    func selectTag(_ tag: MarketTag?) {
        guard selectedTag?.id != tag?.id else { return }
        selectedTag = tag
        Task { await refresh(reset: true) }
    }

    func selectSort(_ sort: MarketSort) {
        guard self.sort != sort else { return }
        self.sort = sort
        Task { await refresh(reset: true) }
    }

    func refresh(reset: Bool) async {
        loadTask?.cancel()
        if reset {
            offset = 0
            canLoadMore = true
            isLoading = true
            errorMessage = nil
        } else {
            guard canLoadMore, !isLoadingMore, !isLoading else { return }
            isLoadingMore = true
        }

        let currentOffset = offset
        let sort = self.sort
        let tagSlug = selectedTag?.slug ?? selectedTag?.label.lowercased()

        loadTask = Task {
            do {
                let page = try await GammaAPI.fetchEvents(
                    limit: pageSize,
                    offset: currentOffset,
                    sort: sort,
                    tagSlug: selectedTag == nil ? nil : tagSlug
                )
                guard !Task.isCancelled else { return }
                if reset {
                    events = page
                } else {
                    let existing = Set(events.map(\.id))
                    events.append(contentsOf: page.filter { !existing.contains($0.id) })
                }
                offset = currentOffset + page.count
                canLoadMore = page.count >= pageSize
                errorMessage = nil
            } catch is CancellationError {
                // ignore
            } catch {
                if reset && events.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
            isLoadingMore = false
        }
        await loadTask?.value
    }

    func loadMoreIfNeeded(current event: PeakEvent) async {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        if idx >= events.count - 4 {
            await refresh(reset: false)
        }
    }

    private func loadTags() async {
        do {
            tags = try await GammaAPI.fetchTags(limit: 30)
        } catch {
            // Tags are optional chrome — fail silently.
        }
    }
}

struct MarketsView: View {
    @StateObject private var model = MarketsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.events.isEmpty {
                    ProgressView("Loading markets…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage, model.events.isEmpty {
                    LoadingErrorView(message: error) {
                        Task { await model.refresh(reset: true) }
                    }
                } else {
                    listContent
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Markets")
            .peakChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            .refreshable {
                await model.refresh(reset: true)
            }
            .onAppear { model.onAppear() }
        }
    }

    private var listContent: some View {
        List {
            if !model.tags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tagChip(title: "All", selected: model.selectedTag == nil) {
                                model.selectTag(nil)
                            }
                            ForEach(model.tags) { tag in
                                tagChip(title: tag.label, selected: model.selectedTag?.id == tag.id) {
                                    model.selectTag(tag)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(model.events) { event in
                    NavigationLink(value: event) {
                        EventRowView(event: event)
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
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: PeakEvent.self) { event in
            EventDetailView(eventID: event.id, seed: event)
        }
    }

    private func tagChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
