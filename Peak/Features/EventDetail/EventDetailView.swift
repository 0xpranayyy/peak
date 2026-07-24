import Charts
import SwiftUI

@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published var event: PeakEvent?
    @Published var selectedMarketID: String?
    @Published var history: [PricePoint] = []
    @Published var book: OrderBook = OrderBook(bids: [], asks: [])
    @Published var liveConnected = false
    @Published var midpoint: Double?
    @Published var spread: Double?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var historyInterval: HistoryInterval = .day

    enum HistoryInterval: String, CaseIterable, Identifiable {
        case hour = "1h"
        case sixHour = "6h"
        case day = "1d"
        case week = "1w"
        case month = "1m"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .hour: return "1H"
            case .sixHour: return "6H"
            case .day: return "1D"
            case .week: return "1W"
            case .month: return "1M"
            }
        }

        var fidelity: Int {
            switch self {
            case .hour: return 1
            case .sixHour: return 5
            case .day: return 15
            case .week: return 60
            case .month: return 180
            }
        }
    }

    private let eventID: String
    private let socket = MarketWebSocket()
    private var loadGeneration = 0

    var selectedMarket: Market? {
        guard let event else { return nil }
        if let id = selectedMarketID {
            return event.markets.first(where: { $0.id == id }) ?? event.markets.first
        }
        return event.markets.first
    }

    init(eventID: String, seed: PeakEvent?) {
        self.eventID = eventID
        self.event = seed
        self.selectedMarketID = seed?.markets.first?.id
    }

    func onAppear() {
        socket.onPrice = { [weak self] asset, price in
            self?.applyLivePrice(asset: asset, price: price)
        }
        socket.onBook = { [weak self] asset, book in
            guard let self, let market = self.selectedMarket,
                  asset == market.yesTokenID || asset == market.noTokenID else { return }
            self.book = book
            self.midpoint = book.midpoint
        }
        socket.onStatusChange = { [weak self] connected in
            self?.liveConnected = connected
        }
        Task { await reload() }
    }

    func onDisappear() {
        socket.disconnect()
    }

    func selectMarket(_ market: Market) {
        selectedMarketID = market.id
        Task { await reloadMarketData() }
    }

    func setInterval(_ interval: HistoryInterval) {
        historyInterval = interval
        Task { await loadHistory() }
    }

    func reload() async {
        isLoading = event == nil
        errorMessage = nil
        do {
            let fresh = try await GammaAPI.fetchEvent(id: eventID)
            event = fresh
            if selectedMarketID == nil || !(fresh.markets.contains { $0.id == selectedMarketID }) {
                selectedMarketID = fresh.markets.first?.id
            }
            await reloadMarketData()
        } catch {
            if event == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func reloadMarketData() async {
        loadGeneration += 1
        let generation = loadGeneration
        await loadHistory()
        guard generation == loadGeneration else { return }
        await loadBookAndQuotes()
        guard generation == loadGeneration else { return }
        reconnectSocket()
    }

    private func loadHistory() async {
        guard let token = selectedMarket?.yesTokenID else {
            history = []
            return
        }
        do {
            history = try await CLOBAPI.fetchPriceHistory(
                tokenID: token,
                interval: historyInterval.rawValue,
                fidelity: historyInterval.fidelity
            )
        } catch {
            // Keep prior chart on transient failures.
        }
    }

    private func loadBookAndQuotes() async {
        guard let token = selectedMarket?.yesTokenID else { return }
        async let bookTask = CLOBAPI.fetchBook(tokenID: token)
        async let midTask = CLOBAPI.fetchMidpoint(tokenID: token)
        async let spreadTask = CLOBAPI.fetchSpread(tokenID: token)
        if let b = try? await bookTask { book = b }
        midpoint = try? await midTask
        spread = try? await spreadTask
        if midpoint == nil { midpoint = book.midpoint }
    }

    private func reconnectSocket() {
        socket.disconnect()
        let ids = (selectedMarket.map { [$0.yesTokenID, $0.noTokenID] } ?? [])
            .compactMap { $0 }
        socket.connect(assetIDs: ids)
    }

    private func applyLivePrice(asset: String, price: Double) {
        guard var event, let idx = event.markets.firstIndex(where: {
            $0.yesTokenID == asset || $0.noTokenID == asset
        }) else { return }
        event.markets[idx].applyLivePrice(tokenID: asset, price: price)
        self.event = event
        if selectedMarket?.yesTokenID == asset || selectedMarket?.noTokenID == asset {
            midpoint = price
        }
    }
}

struct EventDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model: EventDetailViewModel
    @State private var tradeSide: TradeSidePresentation?

    struct TradeSidePresentation: Identifiable {
        let id = UUID()
        let sideLabel: String
        let market: Market
        let isYes: Bool
    }

    init(eventID: String, seed: PeakEvent? = nil) {
        _model = StateObject(wrappedValue: EventDetailViewModel(eventID: eventID, seed: seed))
    }

    var body: some View {
        Group {
            if model.isLoading && model.event == nil {
                ProgressView("Loading event…")
            } else if let error = model.errorMessage, model.event == nil {
                LoadingErrorView(message: error) {
                    Task { await model.reload() }
                }
            } else if let event = model.event {
                content(event)
            }
        }
        .navigationTitle(model.event?.title ?? "Event")
        .navigationBarTitleDisplayMode(.inline)
        .peakChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let event = model.event {
                    Button {
                        env.watchlist.toggle(event.id)
                    } label: {
                        Image(systemName: env.watchlist.contains(event.id) ? "star.fill" : "star")
                    }
                    .accessibilityLabel(env.watchlist.contains(event.id) ? "Remove from Watchlist" : "Add to Watchlist")
                }
            }
        }
        .sheet(item: $tradeSide) { item in
            TradeStubSheet(
                market: item.market,
                sideLabel: item.sideLabel,
                isYes: item.isYes
            )
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    @ViewBuilder
    private func content(_ event: PeakEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(event)

                if event.markets.count > 1 {
                    marketPicker(event.markets)
                }

                if let market = model.selectedMarket {
                    livePriceSection(market)
                    chartSection
                    bookSection
                    tradeButtons(market)
                }
            }
            .padding()
        }
        .background(PeakMaterialBackground())
        .refreshable { await model.reload() }
    }

    private func header(_ event: PeakEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }

            HStack(spacing: 12) {
                Label(PeakFormat.compactCurrency(event.volume), systemImage: "dollarsign.circle")
                Label(PeakFormat.compactCurrency(event.volume24hr) + " 24h", systemImage: "chart.line.uptrend.xyaxis")
                if model.liveConnected {
                    Label("Live", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func marketPicker(_ markets: [Market]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(markets) { market in
                    let selected = market.id == model.selectedMarket?.id
                    Button {
                        model.selectMarket(market)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(market.question)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .frame(width: 160, alignment: .leading)
                            Text(PeakFormat.cents(market.yesPrice))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func livePriceSection(_ market: Market) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MarketOutcomeBar(market: market)
            HStack {
                metric("Mid", model.midpoint.map(PeakFormat.cents) ?? "—")
                metric("Spread", model.spread.map { String(format: "%.1f¢", $0 * 100) } ?? "—")
                metric("Ends", PeakFormat.shortDate(market.endDate))
            }
        }
        .peakGlassCard()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Price")
                    .font(.headline)
                Spacer()
                Picker("Interval", selection: Binding(
                    get: { model.historyInterval },
                    set: { model.setInterval($0) }
                )) {
                    ForEach(EventDetailViewModel.HistoryInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            if model.history.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 180)
                    .overlay {
                        Text("No chart data")
                            .foregroundStyle(.secondary)
                    }
            } else {
                Chart(model.history) { point in
                    LineMark(
                        x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.timestamp))),
                        y: .value("Price", point.price)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)

                    AreaMark(
                        x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.timestamp))),
                        y: .value("Price", point.price)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor.opacity(0.12))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(PeakFormat.cents(v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .peakGlassCard()
    }

    private var bookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Order book")
                .font(.headline)

            if model.book.bids.isEmpty && model.book.asks.isEmpty {
                Text("Book unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    bookColumn(title: "Bids", levels: model.book.bids, emphasize: true)
                    bookColumn(title: "Asks", levels: model.book.asks, emphasize: false)
                }
            }
        }
        .peakGlassCard()
    }

    private func bookColumn(title: String, levels: [OrderBookLevel], emphasize: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(levels.prefix(8)) { level in
                HStack {
                    Text(PeakFormat.cents(level.price))
                        .foregroundStyle(emphasize ? Color.primary : Color.secondary)
                    Spacer()
                    Text(String(format: "%.0f", level.size))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tradeButtons(_ market: Market) -> some View {
        HStack(spacing: 12) {
            Button {
                tradeSide = TradeSidePresentation(sideLabel: market.yesLabel, market: market, isYes: true)
            } label: {
                VStack(spacing: 4) {
                    Text("Buy \(market.yesLabel)")
                        .font(.headline)
                    Text(PeakFormat.cents(market.yesPrice))
                        .font(.subheadline.monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Button {
                tradeSide = TradeSidePresentation(sideLabel: market.noLabel, market: market, isYes: false)
            } label: {
                VStack(spacing: 4) {
                    Text("Buy \(market.noLabel)")
                        .font(.headline)
                    Text(PeakFormat.cents(market.noPrice))
                        .font(.subheadline.monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
        }
    }
}
