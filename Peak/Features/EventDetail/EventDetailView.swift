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
    /// Hard-cap quote UI publishes (~10 Hz) so Chart / ScrollView stay touchable on busy books.
    private static let oddsFlushNanoseconds: UInt64 = 100_000_000
    private static let maxHistoryPoints = 360
    private var oddsFlushTask: Task<Void, Never>?
    private var oddsFlushGeneration = 0
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
        oddsFlushGeneration += 1
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
            let generation = loadGeneration
            await loadHistory(generation: generation)
            guard generation == loadGeneration else { return }
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
        // Seed odds/chart from Gamma immediately so UI isn't blank while CLOB/WS catch up.
        seedDisplayFromSelectedMarket()
        // Live path must not wait on CLOB REST (book/history can stall for seconds).
        reconnectSocket()

        async let historyLoad: Void = loadHistory(generation: generation)
        async let quotesLoad: Void = loadBookAndQuotes(generation: generation)
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
    }

    /// Drop prior-market quotes so wide-spread / mid logic cannot leak across selections.
    private func clearQuoteState() {
        oddsFlushGeneration += 1
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

    private func seedDisplayFromSelectedMarket() {
        guard let market = selectedMarket else { return }
        let seed = market.yesPrice
        guard seed >= 0, seed <= 1 else { return }
        lastTrade = seed
        lastPublishedOdds = seed
        midpoint = midpoint ?? seed
        applyGammaQuoteFallback(from: market, force: true)
        pinChartTip()
    }

    /// When CLOB/WS leave Bid/Ask empty, surface Gamma top-of-book or mid so UI isn't stuck on "—".
    private func applyGammaQuoteFallback(from market: Market? = nil, force: Bool = false) {
        let market = market ?? selectedMarket
        guard let market else { return }
        let mid = market.yesPrice
        guard mid >= 0, mid <= 1 else { return }

        let gammaBid = market.gammaBestBid
        let gammaAsk = market.gammaBestAsk

        if force || bestBid == nil {
            if let gammaBid {
                bestBid = gammaBid
            } else if let gammaAsk {
                // One-sided Gamma quote — mirror a 1¢ touch around mid when possible.
                bestBid = min(mid, max(0.01, gammaAsk - 0.01))
            } else {
                bestBid = mid
            }
        }
        if force || bestAsk == nil {
            if let gammaAsk {
                bestAsk = gammaAsk
            } else if let gammaBid {
                bestAsk = max(mid, min(0.99, gammaBid + 0.01))
            } else {
                bestAsk = mid
            }
        }
        if force || spread == nil, let bid = bestBid, let ask = bestAsk {
            spread = max(0, ask - bid)
        }
        if force || midpoint == nil {
            midpoint = mid
        }
    }

    private func loadHistory(generation: Int) async {
        guard let token = selectedMarket?.yesTokenID else {
            history = []
            return
        }
        isChartLoading = history.count <= 1
        defer { isChartLoading = false }
        let interval = historyInterval.rawValue
        let fidelity = historyInterval.fidelity
        let points = await fetchWithTimeout(seconds: 8, {
            try await CLOBAPI.fetchPriceHistory(
                tokenID: token,
                interval: interval,
                fidelity: fidelity
            )
        })
        guard generation == loadGeneration, let points, !points.isEmpty else { return }
        history = points.count > Self.maxHistoryPoints
            ? Array(points.suffix(Self.maxHistoryPoints))
            : points
    }

    private func loadBookAndQuotes(generation: Int) async {
        guard let token = selectedMarket?.yesTokenID else { return }

        // Book alone usually supplies bid/ask/mid/spread. Avoid 5 parallel CLOB calls
        // that compete with Markets enrich and can stall on a congested host.
        if let book = await fetchWithTimeout(seconds: 6, {
            try await CLOBAPI.fetchBook(tokenID: token)
        }) {
            guard generation == loadGeneration else { return }
            applyBook(book, forYesToken: true)
        }

        guard generation == loadGeneration else { return }
        let needPrices = bestBid == nil || bestAsk == nil
        let needMid = midpoint == nil
        let needSpread = spread == nil
        guard needPrices || needMid || needSpread else {
            syncMarketOddsFromQuotes()
            lastPublishedOdds = displayedYesOdds
            return
        }

        let gap = await withTaskGroup(of: QuoteBatch.self) { group in
            group.addTask {
                async let midTask: Double? = needMid ? (try? await CLOBAPI.fetchMidpoint(tokenID: token)) : nil
                async let spreadTask: Double? = needSpread ? (try? await CLOBAPI.fetchSpread(tokenID: token)) : nil
                async let buyTask: Double? = needPrices ? (try? await CLOBAPI.fetchPrice(tokenID: token, side: "buy")) : nil
                async let sellTask: Double? = needPrices ? (try? await CLOBAPI.fetchPrice(tokenID: token, side: "sell")) : nil
                return QuoteBatch(
                    book: nil,
                    mid: await midTask,
                    spread: await spreadTask,
                    buy: await buyTask,
                    sell: await sellTask
                )
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return QuoteBatch(book: nil, mid: nil, spread: nil, buy: nil, sell: nil)
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }

        guard generation == loadGeneration else { return }

        // Prefer REST values when present; don't clobber fresher WS top-of-book with nils.
        if let mid = gap.mid { midpoint = mid }
        if let spr = gap.spread { spread = spr }
        // CLOB /price?side=buy ≈ best ask (what you pay); side=sell ≈ best bid.
        if let buy = gap.buy { bestAsk = buy }
        if let sell = gap.sell { bestBid = sell }

        // CLOB/WS may still be empty — never leave Bid/Ask as "—" when Gamma mid exists.
        applyGammaQuoteFallback(force: false)

        syncMarketOddsFromQuotes()
        lastPublishedOdds = displayedYesOdds
    }

    private func fetchWithTimeout<T: Sendable>(
        seconds: Double,
        _ work: @escaping @Sendable () async throws -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }

    private struct QuoteBatch: Sendable {
        let book: OrderBook?
        let mid: Double?
        let spread: Double?
        let buy: Double?
        let sell: Double?
    }

    /// Pin live display odds onto the chart tip so the line matches the odds chip.
    /// Prefer in-place tip updates; bound length so Charts can't grow without limit.
    private func pinChartTip() {
        let tip = displayedYesOdds
        guard tip >= 0, tip <= 1 else { return }
        let now = Int(Date().timeIntervalSince1970)
        if let last = history.last {
            if now <= last.timestamp || abs(last.price - tip) <= 0.0005 {
                // Same second or tiny move — mutate tip in place (no append storm).
                if abs(last.price - tip) > 0.00005 || now != last.timestamp {
                    var copy = history
                    copy[copy.count - 1] = PricePoint(timestamp: max(last.timestamp, now), price: tip)
                    history = copy
                }
            } else {
                history.append(PricePoint(timestamp: now, price: tip))
                if history.count > Self.maxHistoryPoints {
                    history = Array(history.suffix(Self.maxHistoryPoints))
                }
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
        let generation = oddsFlushGeneration
        oddsFlushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.oddsFlushNanoseconds)
            defer {
                if oddsFlushGeneration == generation {
                    oddsFlushTask = nil
                }
            }
            guard !Task.isCancelled, oddsFlushGeneration == generation else { return }
            flushStagedQuotes()
            let shouldSync = pendingOddsSync
            let shouldPin = pendingChartPin
            pendingOddsSync = false
            pendingChartPin = false
            let oddsBefore = lastPublishedOdds
            if shouldSync { syncMarketOddsFromQuotes() }
            // Only re-pin / republish history when odds actually moved.
            if shouldPin {
                let odds = displayedYesOdds
                if oddsBefore == nil || abs((oddsBefore ?? odds) - odds) >= 0.0005 {
                    pinChartTip()
                }
            }
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
            // Non-selected tokens: alerts only (no haptics storm from other outcomes).
            PriceAlertMonitor.shared.handleLivePrice(tokenID: asset, price: price)
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
            // Chart tip is flushed with quotes — avoid history @Published every tick.
            scheduleOddsUIUpdate(syncEvent: true, pinChart: true)
            PriceAlertMonitor.shared.handleLivePrice(tokenID: asset, price: price)
            PeakHaptics.oddsMove(tokenID: asset, price: price)
        case .quote:
            stagedMidpoint = yesImplied
            hasStagedQuotes = true
            scheduleOddsUIUpdate(syncEvent: true, pinChart: true)
            // Quotes arrive far more often than trades — skip haptics; alerts still need last/trade-ish moves.
            PriceAlertMonitor.shared.handleLivePrice(tokenID: asset, price: price)
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
    @State private var selectedIsYes = true
    @State private var showFullDescription = false

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
        .navigationTitle("Market")
        .navigationBarTitleDisplayMode(.inline)
        .peakChrome()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let event = model.event {
                    Button {
                        showPriceAlert = true
                    } label: {
                        PeakToolbarCircle(systemImage: "bell")
                    }
                    .accessibilityLabel("Price alert")
                    .disabled(model.selectedMarket == nil)

                    Button {
                        showShareCard = true
                    } label: {
                        PeakToolbarCircle(systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share card")

                    Button {
                        env.watchlist.toggle(event.id)
                    } label: {
                        PeakToolbarCircle(
                            systemImage: env.watchlist.contains(event.id) ? "star.fill" : "star",
                            emphasized: env.watchlist.contains(event.id)
                        )
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
            .environmentObject(TradingRegionStore.shared)
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
            VStack(alignment: .leading, spacing: PeakLayout.stack) {
                header(event)

                if event.markets.count > 1 {
                    marketPicker(event.markets)
                }

                if let market = model.selectedMarket {
                    livePriceSection(market)
                    chartSection
                    bookSection
                    // Spacer so sticky trade bar doesn't cover the book.
                    Color.clear.frame(height: 8)
                }
            }
            .padding(.horizontal, PeakLayout.gutter)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(PeakMaterialBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let market = model.selectedMarket {
                stickyTradeBar(market)
            }
        }
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
            HStack(alignment: .top, spacing: 12) {
                if let url = event.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            PeakCanvas.inset
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                }

                Text(event.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }

            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(showFullDescription ? nil : 2)
                Button(showFullDescription ? "Show less" : "More") {
                    withAnimation(PeakMotion.snappy) {
                        showFullDescription.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(PeakBrand.mid)
            }

            HStack(spacing: 14) {
                Label(PeakFormat.compactCurrency(event.volume), systemImage: "dollarsign.circle")
                Label(PeakFormat.compactCurrency(event.volume24hr) + " 24h", systemImage: "chart.line.uptrend.xyaxis")
                if model.liveConnected {
                    Label("Live", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(PeakTradeStyle.buy)
                        .symbolEffect(
                            .pulse,
                            options: .repeating.speed(0.35),
                            isActive: !reduceMotion
                        )
                        .accessibilityLabel("Live odds")
                }
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .peakAppear()
    }

    private func marketPicker(_ markets: [Market]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Markets")
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(markets) { market in
                        let selected = market.id == model.selectedMarket?.id
                        Button {
                            PeakHaptics.selection()
                            model.selectMarket(market)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(market.question)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 148, alignment: .leading)
                                Text(PeakFormat.cents(market.yesPrice))
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                                    .foregroundStyle(selected ? PeakBrand.mid : .secondary)
                                    // No peakNumeric: this is inside a ForEach and every
                                    // row re-animates on each quote tick. See `metric`.
                            }
                            .padding(12)
                            .background(
                                selected ? PeakBrand.mid.opacity(0.12) : PeakCanvas.elevated,
                                in: PeakLayout.controlShape
                            )
                            .overlay {
                                PeakLayout.controlShape.strokeBorder(
                                    selected ? PeakCanvas.brandRim : PeakCanvas.hairline,
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func livePriceSection(_ market: Market) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MarketOutcomeBar(market: market, displayedYes: model.displayedYesOdds)

            HStack(spacing: 0) {
                metric("Odds", PeakFormat.cents(model.displayedYesOdds))
                metricDivider
                metric("Bid", model.bestBid.map(PeakFormat.cents) ?? "—")
                metricDivider
                metric("Ask", model.bestAsk.map(PeakFormat.cents) ?? "—")
                metricDivider
                metric("Spread", model.spread.map { String(format: "%.1f¢", $0 * 100) } ?? "—")
            }
        }
        .peakContentCard()
        // Live odds move often — animating every tick fights scroll/touch on busy markets.
        .transaction { $0.animation = nil }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(PeakCanvas.hairline)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 6)
    }

    /// Deliberately NOT `peakNumeric`.
    ///
    /// These four update on every quote tick. `peakNumeric` attaches
    /// `.contentTransition(.numericText())` plus `.animation(_:value:)`, and an
    /// animation set on the child is not cleared by the parent's
    /// `.transaction { $0.animation = nil }` — so the strip kept running four
    /// digit transitions per tick despite that line asking for none. On device
    /// this wedged the main thread inside body: opening a market froze the app
    /// until force-quit, with the paused stack sitting in metric → peakNumeric.
    ///
    /// Live numbers here should just change. Keep `peakNumeric` for values that
    /// move occasionally, not for a live quote strip.
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Chart")
                    .font(.headline)
                Spacer()
                Text(PeakFormat.cents(model.displayedYesOdds))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(PeakBrand.mid)
                    // No peakNumeric: displayedYesOdds moves on every tick. See `metric`.
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EventDetailViewModel.HistoryInterval.allCases) { interval in
                        let on = model.historyInterval == interval
                        Button {
                            model.setInterval(interval)
                        } label: {
                            Text(interval.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(
                                    on ? PeakBrand.deep : PeakCanvas.inset,
                                    in: Capsule(style: .continuous)
                                )
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(on ? Color.clear : PeakCanvas.hairline, lineWidth: 1)
                                }
                                .foregroundStyle(on ? Color.white : Color.secondary)
                                .frame(minHeight: 32)
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
                    .frame(height: 180)
            } else if model.history.isEmpty {
                RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                    .fill(PeakCanvas.inset)
                    .frame(height: 180)
                    .overlay {
                        Text("No chart data yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
            } else {
                let series = PeakBrand.mid
                let chartPoints = sanitizedHistory
                let prices = chartPoints.map(\.price)
                let lo = max(0, (prices.min() ?? 0) - 0.03)
                let hi = min(1, (prices.max() ?? 1) + 0.03)

                Chart {
                    ForEach(chartPoints) { point in
                        LineMark(
                            x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.timestamp))),
                            y: .value("Odds", point.price)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(series)
                        .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))

                        AreaMark(
                            x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.timestamp))),
                            y: .value("Odds", point.price)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [series.opacity(0.22), series.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    if let last = chartPoints.last {
                        PointMark(
                            x: .value("Time", Date(timeIntervalSince1970: TimeInterval(last.timestamp))),
                            y: .value("Odds", last.price)
                        )
                        .foregroundStyle(series)
                        .symbolSize(42)
                    }
                }
                .chartYScale(domain: lo...max(lo + 0.01, hi))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(PeakCanvas.hairline)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(PeakFormat.cents(v))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(PeakCanvas.hairline.opacity(0.6))
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 180)
            }
        }
        .peakContentCard()
    }

    /// Drop obvious bad tip spikes (e.g. pinned 0¢) that warp the chart.
    /// Avoid sorting the full series on every body pass — sample a fixed window.
    private var sanitizedHistory: [PricePoint] {
        let points = model.history
        guard points.count >= 3, let last = points.last else { return points }
        let sample = points.suffix(48).dropLast()
        guard !sample.isEmpty else { return points }
        let sorted = sample.map(\.price).sorted()
        let median = sorted[sorted.count / 2]
        if abs(last.price - median) > 0.45, last.price < 0.05 || last.price > 0.95 {
            return Array(points.dropLast()) + [PricePoint(timestamp: last.timestamp, price: model.displayedYesOdds)]
        }
        return points
    }

    private var bookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Order book")
                .font(.headline)

            if model.book.bids.isEmpty && model.book.asks.isEmpty {
                Text("Order book isn’t available right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    bookColumn(
                        title: "Bids",
                        levels: Array(model.book.bids.prefix(6)),
                        color: PeakTradeStyle.buy,
                        alignTrailing: false
                    )
                    bookColumn(
                        title: "Asks",
                        levels: Array(model.book.asks.prefix(6)),
                        color: PeakTradeStyle.sell,
                        alignTrailing: true
                    )
                }
            }
        }
        .peakContentCard()
    }

    private func bookColumn(
        title: String,
        levels: [OrderBookLevel],
        color: Color,
        alignTrailing: Bool
    ) -> some View {
        let maxSize = max(levels.map(\.size).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
                Text("Size")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            if levels.isEmpty {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(levels) { level in
                    ZStack(alignment: alignTrailing ? .trailing : .leading) {
                        GeometryReader { geo in
                            let width = geo.size.width * CGFloat(min(1, level.size / maxSize))
                            Rectangle()
                                .fill(color.opacity(0.12))
                                .frame(width: max(4, width))
                                .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
                        }
                        HStack {
                            Text(PeakFormat.cents(level.price))
                                .foregroundStyle(color)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(compactSize(level.size))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.monospacedDigit())
                        .padding(.vertical, 5)
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 26)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactSize(_ size: Double) -> String {
        if size >= 1_000_000 { return String(format: "%.1fM", size / 1_000_000) }
        if size >= 1_000 { return String(format: "%.1fK", size / 1_000) }
        return String(format: "%.0f", size)
    }

    private func stickyTradeBar(_ market: Market) -> some View {
        VStack(spacing: 10) {
            Picker("Share", selection: $selectedIsYes) {
                Text(market.yesLabel).tag(true)
                Text(market.noLabel).tag(false)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
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
        .padding(.horizontal, PeakLayout.gutter)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(PeakCanvas.background.opacity(0.94))
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(PeakCanvas.hairline)
                        .frame(height: 1)
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
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(subtitle)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .peakNumeric(value: subtitle)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(color, in: PeakLayout.ctaShape)
            .contentShape(PeakLayout.ctaShape)
        }
        .peakPressable()
        .accessibilityLabel("\(title) \(accessibilitySide) at \(subtitle)")
    }
}
