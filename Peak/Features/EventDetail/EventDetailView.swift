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
    @Published var bestBid: Double?
    @Published var bestAsk: Double?
    @Published var lastTrade: Double?
    @Published var isLoading = false
    @Published var isChartLoading = false
    @Published var errorMessage: String?
    @Published var historyInterval: HistoryInterval = .day

    enum HistoryInterval: String, CaseIterable, Identifiable {
        case hour = "1h"
        case sixHour = "6h"
        case day = "1d"
        case week = "1w"
        case month = "1m"
        case max = "max"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .hour: return "1H"
            case .sixHour: return "6H"
            case .day: return "1D"
            case .week: return "1W"
            case .month: return "1M"
            case .max: return "ALL"
            }
        }

        /// Fidelity in minutes — per Polymarket prices-history docs.
        var fidelity: Int {
            switch self {
            case .hour: return 1
            case .sixHour: return 5
            case .day: return 15
            case .week: return 60
            case .month: return 240
            case .max: return 720
            }
        }
    }

    private let eventID: String
    private let socket = MarketWebSocket()
    private var loadGeneration = 0
    /// Coalesce quote-driven UI publishes (~150ms) so @Published doesn't thrash every tick.
    private var oddsFlushTask: Task<Void, Never>?
    private var pendingOddsSync = false
    private var pendingChartPin = false
    private var lastPublishedOdds: Double?
    private var stagedMidpoint: Double?
    private var stagedSpread: Double?
    private var stagedBestBid: Double?
    private var stagedBestAsk: Double?
    private var stagedLastTrade: Double?
    private var stagedBook: OrderBook?
    private var hasStagedQuotes = false

    var selectedMarket: Market? {
        guard let event else { return nil }
        if let id = selectedMarketID {
            return event.markets.first(where: { $0.id == id }) ?? event.markets.first
        }
        return event.markets.first
    }

    /// Odds shown in UI — midpoint unless wide spread, then last trade (Polymarket rule).
    var displayedYesOdds: Double {
        PeakTradeStyle.displayedOdds(
            mid: midpoint,
            spread: spread,
            lastTrade: lastTrade,
            fallback: selectedMarket?.yesPrice ?? 0.5
        )
    }

    init(eventID: String, seed: PeakEvent?) {
        self.eventID = eventID
        self.event = seed
        self.selectedMarketID = seed?.markets.first?.id
    }

    func onAppear() {
        socket.onPrice = { [weak self] asset, price, kind in
            self?.applyLivePrice(asset: asset, price: price, kind: kind)
        }
        socket.onBook = { [weak self] asset, book in
            guard let self, let market = self.selectedMarket,
                  asset == market.yesTokenID || asset == market.noTokenID else { return }
            self.stageBook(book, forYesToken: asset == market.yesTokenID)
        }
        socket.onTopOfBook = { [weak self] asset, bid, ask in
            guard let self, let market = self.selectedMarket,
                  asset == market.yesTokenID else { return }
            if let bid { self.stagedBestBid = bid }
            if let ask { self.stagedBestAsk = ask }
            if let bid, let ask, bid > 0, ask > 0 {
                self.stagedMidpoint = (bid + ask) / 2
                self.stagedSpread = ask - bid
            }
            self.hasStagedQuotes = true
            self.scheduleOddsUIUpdate(syncEvent: true, pinChart: true)
        }
        socket.onStatusChange = { [weak self] connected in
            self?.liveConnected = connected
        }
        Task { await reload() }
    }

    func onDisappear() {
        oddsFlushTask?.cancel()
        oddsFlushTask = nil
        socket.disconnect()
    }

    func selectMarket(_ market: Market) {
        selectedMarketID = market.id
        Task { await reloadMarketData() }
    }

    func setInterval(_ interval: HistoryInterval) {
        historyInterval = interval
        Task {
            await loadHistory()
            pinChartTip()
        }
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
                errorMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t load this event. Try again.")
            }
        }
        isLoading = false
    }

    private func reloadMarketData() async {
        loadGeneration += 1
        let generation = loadGeneration
        clearQuoteState()
        async let historyLoad: Void = loadHistory()
        async let quotesLoad: Void = loadBookAndQuotes()
        _ = await (historyLoad, quotesLoad)
        guard generation == loadGeneration else { return }
        // Prefer CLOB history tip, then Gamma outcome price — never midpoint.
        if lastTrade == nil {
            if let tip = history.last?.price, tip >= 0, tip <= 1 {
                lastTrade = tip
            } else {
                lastTrade = selectedMarket?.yesPrice
            }
        }
        pinChartTip()
        reconnectSocket()
    }

    /// Drop prior-market quotes so wide-spread / mid logic cannot leak across selections.
    private func clearQuoteState() {
        oddsFlushTask?.cancel()
        oddsFlushTask = nil
        pendingOddsSync = false
        pendingChartPin = false
        lastPublishedOdds = nil
        stagedMidpoint = nil
        stagedSpread = nil
        stagedBestBid = nil
        stagedBestAsk = nil
        stagedLastTrade = nil
        stagedBook = nil
        hasStagedQuotes = false
        midpoint = nil
        spread = nil
        bestBid = nil
        bestAsk = nil
        lastTrade = nil
        book = OrderBook(bids: [], asks: [])
        history = []
    }

    private func loadHistory() async {
        guard let token = selectedMarket?.yesTokenID else {
            history = []
            return
        }
        isChartLoading = history.isEmpty
        defer { isChartLoading = false }
        do {
            let points = try await CLOBAPI.fetchPriceHistory(
                tokenID: token,
                interval: historyInterval.rawValue,
                fidelity: historyInterval.fidelity
            )
            history = points
        } catch {
            // Keep prior chart on transient failures (cleared already on market switch).
        }
    }

    private func loadBookAndQuotes() async {
        guard let token = selectedMarket?.yesTokenID else { return }
        async let bookTask = CLOBAPI.fetchBook(tokenID: token)
        async let midTask = CLOBAPI.fetchMidpoint(tokenID: token)
        async let spreadTask = CLOBAPI.fetchSpread(tokenID: token)
        async let buyTask = CLOBAPI.fetchPrice(tokenID: token, side: "buy")
        async let sellTask = CLOBAPI.fetchPrice(tokenID: token, side: "sell")

        if let b = try? await bookTask {
            applyBook(b, forYesToken: true)
        }

        let mid = try? await midTask
        let spr = try? await spreadTask
        let buy = try? await buyTask
        let sell = try? await sellTask

        if let mid { midpoint = mid }
        if let spr { spread = spr }
        // CLOB /price?side=buy ≈ best ask (what you pay); side=sell ≈ best bid.
        if let buy { bestAsk = buy }
        if let sell { bestBid = sell }
        // Never seed lastTrade from midpoint — that defeats the wide-spread rule.

        syncMarketOddsFromQuotes()
        lastPublishedOdds = displayedYesOdds
    }

    /// Pin live display odds onto the chart tip so the line matches the odds chip.
    private func pinChartTip() {
        let tip = displayedYesOdds
        guard tip >= 0, tip <= 1 else { return }
        let now = Int(Date().timeIntervalSince1970)
        if let last = history.last {
            if abs(last.price - tip) > 0.0005 {
                history.append(PricePoint(timestamp: now, price: tip))
            } else if now - last.timestamp >= 0 {
                var copy = history
                copy[copy.count - 1] = PricePoint(timestamp: max(last.timestamp, now), price: tip)
                history = copy
            }
        } else {
            history = [PricePoint(timestamp: now, price: tip)]
        }
    }

    private func applyBook(_ book: OrderBook, forYesToken: Bool) {
        guard forYesToken else { return }
        self.book = book
        bestBid = book.bestBid ?? bestBid
        bestAsk = book.bestAsk ?? bestAsk
        if let mid = book.midpoint {
            midpoint = mid
        }
        if let bid = book.bestBid, let ask = book.bestAsk {
            spread = ask - bid
        }
        syncMarketOddsFromQuotes()
        lastPublishedOdds = displayedYesOdds
        pinChartTip()
    }

    private func stageBook(_ book: OrderBook, forYesToken: Bool) {
        guard forYesToken else { return }
        stagedBook = book
        if let bid = book.bestBid { stagedBestBid = bid }
        if let ask = book.bestAsk { stagedBestAsk = ask }
        if let mid = book.midpoint { stagedMidpoint = mid }
        if let bid = book.bestBid, let ask = book.bestAsk {
            stagedSpread = ask - bid
        }
        hasStagedQuotes = true
        scheduleOddsUIUpdate(syncEvent: true, pinChart: true)
    }

    private func syncMarketOddsFromQuotes() {
        guard var event, let idx = event.markets.firstIndex(where: { $0.id == selectedMarket?.id }) else { return }
        let odds = displayedYesOdds
        if let last = lastPublishedOdds, abs(last - odds) < 0.001 {
            return
        }
        var market = event.markets[idx]
        if let yesToken = market.yesTokenID, !yesToken.isEmpty {
            market.applyLivePrice(tokenID: yesToken, price: odds)
        } else if market.outcomePrices.isEmpty {
            market.outcomePrices = [odds, max(0, 1 - odds)]
        } else {
            market.outcomePrices[0] = odds
            if market.outcomePrices.count > 1 {
                market.outcomePrices[1] = max(0, 1 - odds)
            }
        }
        event.markets[idx] = market
        self.event = event
        lastPublishedOdds = odds
    }

    /// Batch quote-driven event/chart publishes so live ticks don't rebuild the detail tree every message.
    private func scheduleOddsUIUpdate(syncEvent: Bool, pinChart: Bool) {
        if syncEvent { pendingOddsSync = true }
        if pinChart { pendingChartPin = true }
        guard oddsFlushTask == nil else { return }
        oddsFlushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                oddsFlushTask = nil
                return
            }
            flushStagedQuotes()
            let shouldSync = pendingOddsSync
            let shouldPin = pendingChartPin
            pendingOddsSync = false
            pendingChartPin = false
            oddsFlushTask = nil
            if shouldSync { syncMarketOddsFromQuotes() }
            if shouldPin { pinChartTip() }
        }
    }

    private func flushStagedQuotes() {
        guard hasStagedQuotes else { return }
        hasStagedQuotes = false
        if let stagedBook { book = stagedBook }
        if let stagedMidpoint { midpoint = stagedMidpoint }
        if let stagedSpread { spread = stagedSpread }
        if let stagedBestBid { bestBid = stagedBestBid }
        if let stagedBestAsk { bestAsk = stagedBestAsk }
        if let stagedLastTrade { lastTrade = stagedLastTrade }
        stagedBook = nil
        stagedMidpoint = nil
        stagedSpread = nil
        stagedBestBid = nil
        stagedBestAsk = nil
        stagedLastTrade = nil
    }

    private func reconnectSocket() {
        socket.disconnect()
        let ids = (selectedMarket.map { [$0.yesTokenID, $0.noTokenID] } ?? [])
            .compactMap { $0 }
        socket.connect(assetIDs: ids)
    }

    private func applyLivePrice(asset: String, price: Double, kind: MarketWebSocket.PriceKind) {
        guard let market = selectedMarket,
              market.yesTokenID == asset || market.noTokenID == asset else {
            PriceAlertMonitor.shared.handleLivePrice(tokenID: asset, price: price)
            PeakHaptics.oddsMove(tokenID: asset, price: price)
            return
        }

        let yesImplied: Double
        if market.yesTokenID == asset {
            yesImplied = price
        } else {
            yesImplied = max(0, min(1, 1 - price))
        }

        switch kind {
        case .lastTrade:
            stagedLastTrade = yesImplied
            hasStagedQuotes = true
            appendLiveChartPoint(yesImplied)
            scheduleOddsUIUpdate(syncEvent: true, pinChart: false)
        case .quote:
            stagedMidpoint = yesImplied
            hasStagedQuotes = true
            scheduleOddsUIUpdate(syncEvent: true, pinChart: true)
        }

        PriceAlertMonitor.shared.handleLivePrice(tokenID: asset, price: price)
        PeakHaptics.oddsMove(tokenID: asset, price: price)
    }

    private func appendLiveChartPoint(_ price: Double) {
        let now = Int(Date().timeIntervalSince1970)
        if let last = history.last, now - last.timestamp < 2 {
            var copy = history
            copy[copy.count - 1] = PricePoint(timestamp: now, price: price)
            history = copy
        } else {
            history.append(PricePoint(timestamp: now, price: price))
        }
    }

    func buyPrice(isYes: Bool) -> Double {
        // Buying pays the ask. No ask ≈ 1 − Yes bid.
        if isYes {
            return bestAsk ?? displayedYesOdds
        }
        return max(0.01, min(0.99, 1 - (bestBid ?? displayedYesOdds)))
    }

    func sellPrice(isYes: Bool) -> Double {
        // Selling receives the bid. No bid ≈ 1 − Yes ask.
        if isYes {
            return bestBid ?? displayedYesOdds
        }
        return max(0.01, min(0.99, 1 - (bestAsk ?? displayedYesOdds)))
    }
}

struct EventDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: EventDetailViewModel
    @State private var trade: TradePresentation?
    @State private var showShareCard = false
    @State private var showPriceAlert = false
    /// Which outcome share is active for the single Buy / Sell pair.
    @State private var selectedIsYes = true

    struct TradePresentation: Identifiable {
        let id = UUID()
        let market: Market
        let isYes: Bool
        let action: TradeAction
    }

    enum TradeAction {
        case buy, sell
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let event = model.event {
                    Button {
                        showPriceAlert = true
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel("Price alert")
                    .disabled(model.selectedMarket == nil)

                    Button {
                        showShareCard = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share card")

                    Button {
                        env.watchlist.toggle(event.id)
                    } label: {
                        Image(systemName: env.watchlist.contains(event.id) ? "star.fill" : "star")
                    }
                    .accessibilityLabel(env.watchlist.contains(event.id) ? "Remove from Watchlist" : "Add to Watchlist")
                }
            }
        }
        .sheet(item: $trade) { item in
            TradeStubSheet(
                market: item.market,
                isYes: item.isYes,
                action: item.action == .buy ? .buy : .sell,
                quotePrice: item.action == .buy
                    ? model.buyPrice(isYes: item.isYes)
                    : model.sellPrice(isYes: item.isYes)
            )
            .environmentObject(env)
            .environmentObject(env.tradingConfig)
            .environmentObject(PrivyAuthService.shared)
            .environmentObject(TradingPathStore.shared)
        }
        .sheet(isPresented: $showShareCard) {
            if let event = model.event {
                ShareMarketSheet(
                    event: event,
                    market: model.selectedMarket,
                    history: model.history
                )
            }
        }
        .sheet(isPresented: $showPriceAlert) {
            if let event = model.event, let market = model.selectedMarket {
                PriceAlertComposerSheet(event: event, market: market)
            }
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
        .refreshable {
            await model.reload()
            PeakHaptics.refresh()
        }
        .onChange(of: model.selectedMarket?.id) { _, _ in
            selectedIsYes = true
        }
    }

    private func header(_ event: PeakEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = event.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.secondary.opacity(0.12)
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        Color.secondary.opacity(0.12)
                    }
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            }

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
                    Label {
                        Text("Live")
                    } icon: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .symbolEffect(
                                .pulse,
                                options: .repeating.speed(0.35),
                                isActive: !reduceMotion
                            )
                    }
                    .foregroundStyle(PeakTradeStyle.buy)
                    .accessibilityLabel("Live odds")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .peakAppear()
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
                        .background(
                            selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
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
            MarketOutcomeBar(market: market, displayedYes: model.displayedYesOdds)

            HStack {
                metric("Odds", PeakFormat.cents(model.displayedYesOdds))
                metric("Bid", model.bestBid.map(PeakFormat.cents) ?? "—")
                metric("Ask", model.bestAsk.map(PeakFormat.cents) ?? "—")
                metric("Spread", model.spread.map { String(format: "%.1f¢", $0 * 100) } ?? "—")
            }
        }
        .peakContentCard()
        .animation(PeakMotion.soft, value: model.displayedYesOdds)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .peakNumeric(value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Odds")
                    .font(.headline)
                Spacer()
                Text(PeakFormat.cents(model.displayedYesOdds))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(PeakBrand.mid)
                    .peakNumeric(value: model.displayedYesOdds)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EventDetailViewModel.HistoryInterval.allCases) { interval in
                        let on = model.historyInterval == interval
                        Button {
                            model.setInterval(interval)
                        } label: {
                            Text(interval.title)
                                .font(.caption.weight(.semibold))
                                .frame(minHeight: PeakLayout.minTap)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    on ? Color.accentColor : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                                )
                                .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityLabel("Chart interval \(interval.title)")
                    }
                }
            }

            if model.isChartLoading && model.history.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            } else if model.history.isEmpty {
                RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
                    .frame(height: 200)
                    .overlay {
                        ZStack {
                            PeakChartPlaceholder()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 28)
                            VStack(spacing: 8) {
                                Spacer()
                                Text("No chart data yet")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 16)
                            }
                        }
                    }
            } else {
                let series = PeakBrand.mid
                let prices = model.history.map(\.price)
                let lo = max(0, (prices.min() ?? 0) - 0.04)
                let hi = min(1, (prices.max() ?? 1) + 0.04)

                Chart {
                    ForEach(model.history) { point in
                        LineMark(
                            x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.timestamp))),
                            y: .value("Odds", point.price)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(series)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        AreaMark(
                            x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.timestamp))),
                            y: .value("Odds", point.price)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [series.opacity(0.26), series.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    RuleMark(y: .value("Now", model.displayedYesOdds))
                        .foregroundStyle(series.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    if let last = model.history.last {
                        PointMark(
                            x: .value("Time", Date(timeIntervalSince1970: TimeInterval(last.timestamp))),
                            y: .value("Odds", last.price)
                        )
                        .foregroundStyle(series)
                        .symbolSize(48)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.secondary.opacity(0.22))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(PeakFormat.cents(v))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.secondary.opacity(0.14))
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
            }
        }
        .peakContentCard()
    }

    private var bookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Order book")
                .font(.headline)

            if model.book.bids.isEmpty && model.book.asks.isEmpty {
                Text("Order book isn’t available right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    bookColumn(title: "Bids", levels: model.book.bids, color: PeakTradeStyle.buy)
                    bookColumn(title: "Asks", levels: model.book.asks, color: PeakTradeStyle.sell)
                }
            }
        }
        .peakContentCard()
    }

    private func bookColumn(title: String, levels: [OrderBookLevel], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            ForEach(levels.prefix(8)) { level in
                HStack {
                    Text(PeakFormat.cents(level.price))
                        .foregroundStyle(color)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Trade")
                .font(.headline)

            // Pick one share, then a single Buy + Sell for that share.
            Picker("Share", selection: $selectedIsYes) {
                Text(market.yesLabel).tag(true)
                Text(market.noLabel).tag(false)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                let side = selectedIsYes ? market.yesLabel : market.noLabel
                tradeButton(
                    title: "Buy",
                    subtitle: PeakFormat.cents(model.buyPrice(isYes: selectedIsYes)),
                    color: PeakTradeStyle.buy,
                    accessibilitySide: side
                ) {
                    trade = TradePresentation(market: market, isYes: selectedIsYes, action: .buy)
                }
                tradeButton(
                    title: "Sell",
                    subtitle: PeakFormat.cents(model.sellPrice(isYes: selectedIsYes)),
                    color: PeakTradeStyle.sell,
                    accessibilitySide: side
                ) {
                    trade = TradePresentation(market: market, isYes: selectedIsYes, action: .sell)
                }
            }
        }
    }

    private func tradeButton(
        title: String,
        subtitle: String,
        color: Color,
        accessibilitySide: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .opacity(0.9)
                    .peakNumeric(value: subtitle)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .frame(minHeight: 50)
            .background(color, in: RoundedRectangle(cornerRadius: PeakLayout.ctaRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PeakLayout.ctaRadius, style: .continuous))
        }
        .peakPressable()
        .accessibilityLabel("\(title) \(accessibilitySide) at \(subtitle)")
    }
}
