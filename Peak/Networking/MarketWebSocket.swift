import Foundation
import os

/// Caps shared by MainActor and background parse/coalesce (must stay nonisolated).
private enum MarketWebSocketLimits {
    static let uiFlushIntervalNanoseconds: UInt64 = 80_000_000
    static let maxReconnectDelaySeconds: Double = 20
    static let maxBookDepth = 8
    static let maxBookParseLevels = 48
}

/// Live prices via Polymarket's public CLOB Market WebSocket channel.
/// Subscribes with `assets_ids` and sends `PING` every 10 seconds.
///
/// JSON is parsed off the main actor. Parsed quotes are coalesced and flushed
/// to MainActor callbacks at a hard cap (~12 Hz) so busy markets cannot stall touch.
@MainActor
final class MarketWebSocket {
    static let url = URL(string: "wss://ws-subscriptions-clob.polymarket.com/ws/market")!

    /// Distinguishes executed trades from quote/mid updates.
    enum PriceKind: Sendable {
        /// `last_trade_price` — actual fill price.
        case lastTrade
        /// Derived from best bid/ask (`price_change`, `book`, `best_bid_ask`).
        case quote
    }

    private enum ParsedEvent: Sendable {
        case lastTrade(asset: String, price: Double)
        case quote(asset: String, bid: Double?, ask: Double?)
        case book(asset: String, book: OrderBook, bestBid: Double?, bestAsk: Double?)
    }

    /// Latest coalesced state per asset — flushed to UI at most once per interval.
    private struct PendingAsset: Sendable {
        var bid: Double?
        var ask: Double?
        var mid: Double?
        var lastTrade: Double?
        var book: OrderBook?
        var hasQuote = false
        var hasTrade = false
        var hasBook = false
    }

    private struct PendingBuffer: Sendable {
        var assets: [String: PendingAsset] = [:]
        var flushScheduled = false
    }

    private var task: URLSessionWebSocketTask?
    private var assetIDs: [String] = []
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private var wantsConnection = false
    private var reconnectTask: Task<Void, Never>?
    private var receiveGeneration = 0
    private(set) var isConnected = false

    /// Coalesce off MainActor; only the flush hops back.
    /// nonisolated(unsafe): lock is thread-safe; background parse tasks must not hop MainActor.
    nonisolated(unsafe) private let pending = OSAllocatedUnfairLock(initialState: PendingBuffer())

    var onPrice: ((String, Double, PriceKind) -> Void)?
    var onBook: ((String, OrderBook) -> Void)?
    /// Top-of-book from `price_change` / `best_bid_ask` (asset, bestBid, bestAsk).
    var onTopOfBook: ((String, Double?, Double?) -> Void)?
    var onStatusChange: ((Bool) -> Void)?

    func connect(assetIDs: [String]) {
        wantsConnection = true
        self.assetIDs = assetIDs.filter { !$0.isEmpty }
        open()
    }

    func disconnect() {
        wantsConnection = false
        receiveGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        pending.withLock { buffer in
            buffer.assets.removeAll(keepingCapacity: false)
            buffer.flushScheduled = false
        }
        setConnected(false)
    }

    private func open() {
        guard wantsConnection, !assetIDs.isEmpty else { return }
        receiveGeneration += 1
        let generation = receiveGeneration
        reconnectTask?.cancel()
        reconnectTask = nil
        pending.withLock { buffer in
            buffer.assets.removeAll(keepingCapacity: true)
            buffer.flushScheduled = false
        }
        task?.cancel(with: .normalClosure, reason: nil)
        let t = URLSession.shared.webSocketTask(with: Self.url)
        task = t
        t.resume()
        subscribe()
        receiveLoop(generation: generation)
        startPing()
    }

    private func subscribe() {
        // `custom_feature_enabled` unlocks `best_bid_ask` (and related) events.
        let payload: [String: Any] = [
            "assets_ids": assetIDs,
            "type": "market",
            "custom_feature_enabled": true,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { [weak self] error in
            Task { @MainActor in
                guard let self, self.wantsConnection else { return }
                if error == nil {
                    self.setConnected(true)
                    self.reconnectAttempts = 0
                } else {
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func receiveLoop(generation: Int) {
        guard wantsConnection, generation == receiveGeneration else { return }
        task?.receive { [weak self] result in
            // Keep the socket pump off MainActor: parse + coalesce on a utility task,
            // then only hop for the next receive / reconnect bookkeeping.
            switch result {
            case .success(let message):
                let text: String?
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(data: data, encoding: .utf8)
                @unknown default:
                    text = nil
                }

                if let text, text != "PONG", let self {
                    // Parse + coalesce without touching MainActor; only the ~12 Hz flush hops.
                    Task.detached(priority: .utility) { [weak self] in
                        guard let self else { return }
                        let events = MarketWebSocket.parse(text)
                        guard !events.isEmpty else { return }
                        self.enqueueOffMain(events, generation: generation)
                    }
                }

                Task { @MainActor [weak self] in
                    guard let self, generation == self.receiveGeneration, self.wantsConnection else { return }
                    self.receiveLoop(generation: generation)
                }
            case .failure:
                Task { @MainActor [weak self] in
                    guard let self, generation == self.receiveGeneration else { return }
                    self.setConnected(false)
                    self.scheduleReconnect()
                }
            }
        }
    }

    /// Merge into the lock-backed buffer on the caller’s thread (utility), then arm one MainActor flush.
    nonisolated private func enqueueOffMain(_ events: [ParsedEvent], generation: Int) {
        let shouldSchedule = pending.withLock { buffer -> Bool in
            for event in events {
                switch event {
                case let .lastTrade(asset, price):
                    var row = buffer.assets[asset] ?? PendingAsset()
                    row.lastTrade = price
                    row.hasTrade = true
                    buffer.assets[asset] = row
                case let .quote(asset, bid, ask):
                    var row = buffer.assets[asset] ?? PendingAsset()
                    if let bid { row.bid = bid }
                    if let ask { row.ask = ask }
                    if let bid, let ask, bid > 0, ask > 0 {
                        row.mid = (bid + ask) / 2
                    }
                    row.hasQuote = true
                    buffer.assets[asset] = row
                case let .book(asset, book, bestBid, bestAsk):
                    var row = buffer.assets[asset] ?? PendingAsset()
                    row.book = book
                    row.hasBook = true
                    if let bestBid { row.bid = bestBid }
                    if let bestAsk { row.ask = bestAsk }
                    if let bestBid, let bestAsk, bestBid > 0, bestAsk > 0 {
                        row.mid = (bestBid + bestAsk) / 2
                    }
                    row.hasQuote = true
                    buffer.assets[asset] = row
                }
            }
            guard !buffer.flushScheduled else { return false }
            buffer.flushScheduled = true
            return true
        }

        guard shouldSchedule else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: MarketWebSocketLimits.uiFlushIntervalNanoseconds)
            self?.flushPending(generation: generation)
        }
    }

    private func flushPending(generation: Int) {
        let snapshot: [String: PendingAsset] = pending.withLock { buffer in
            buffer.flushScheduled = false
            let copy = buffer.assets
            buffer.assets.removeAll(keepingCapacity: true)
            return copy
        }
        guard wantsConnection, generation == receiveGeneration, !snapshot.isEmpty else { return }

        for (asset, row) in snapshot {
            if row.hasBook, let book = row.book {
                onBook?(asset, book)
            }
            if row.hasQuote, row.bid != nil || row.ask != nil {
                onTopOfBook?(asset, row.bid, row.ask)
            }
            if row.hasTrade, let price = row.lastTrade {
                onPrice?(asset, price, .lastTrade)
            }
            if row.hasQuote, let mid = row.mid, mid > 0, mid < 1 {
                onPrice?(asset, mid, .quote)
            }
        }
    }

    private nonisolated static func parse(_ text: String) -> [ParsedEvent] {
        guard let data = text.data(using: .utf8) else { return [] }
        let root = try? JSONSerialization.jsonObject(with: data)
        let events: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            events = arr
        } else if let obj = root as? [String: Any] {
            events = [obj]
        } else {
            return []
        }

        var parsed: [ParsedEvent] = []
        parsed.reserveCapacity(min(events.count, 32))
        for event in events {
            let type = (event["event_type"] as? String ?? event["type"] as? String ?? "").lowercased()
            switch type {
            case "price_change":
                // `price` on each change is the *level affected*, not the market mid.
                if let nested = event["price_changes"] as? [[String: Any]] {
                    for change in nested {
                        if let quote = parseQuote(change) {
                            parsed.append(quote)
                        }
                    }
                } else if let quote = parseQuote(event) {
                    parsed.append(quote)
                }
            case "last_trade_price":
                if let asset = event["asset_id"] as? String,
                   let p = double(event["price"]),
                   p >= 0, p <= 1 {
                    parsed.append(.lastTrade(asset: asset, price: p))
                }
            case "best_bid_ask":
                if let quote = parseQuote(event) {
                    parsed.append(quote)
                }
            case "book":
                if let asset = event["asset_id"] as? String {
                    let bids = parseLevels(event["bids"], side: .bid)
                        .sorted { $0.price > $1.price }
                    let asks = parseLevels(event["asks"], side: .ask)
                        .sorted { $0.price < $1.price }
                    let trimmed = OrderBook(
                        bids: Array(bids.prefix(MarketWebSocketLimits.maxBookDepth)),
                        asks: Array(asks.prefix(MarketWebSocketLimits.maxBookDepth))
                    )
                    let bestBid = trimmed.bestBid
                    let bestAsk = trimmed.bestAsk
                    if !trimmed.bids.isEmpty || !trimmed.asks.isEmpty || bestBid != nil || bestAsk != nil {
                        parsed.append(.book(asset: asset, book: trimmed, bestBid: bestBid, bestAsk: bestAsk))
                    }
                }
            default:
                break
            }
        }
        return parsed
    }

    private nonisolated static func parseQuote(_ dict: [String: Any]) -> ParsedEvent? {
        guard let asset = dict["asset_id"] as? String else { return nil }
        let bid = double(dict["best_bid"])
        let ask = double(dict["best_ask"])
        guard bid != nil || ask != nil else { return nil }
        return .quote(asset: asset, bid: bid, ask: ask)
    }

    private nonisolated static func parseLevels(_ raw: Any?, side: OrderBookLevel.Side) -> [OrderBookLevel] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        // Cap before sorting — full CLOB books can be huge and must stay off MainActor.
        let limited = rows.prefix(MarketWebSocketLimits.maxBookParseLevels)
        return limited.compactMap { row in
            guard let price = double(row["price"]),
                  let size = double(row["size"]) else { return nil }
            return OrderBookLevel(price: price, size: size, side: side)
        }
    }

    private nonisolated static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.wantsConnection else { return }
                self.task?.send(.string("PING")) { _ in }
            }
        }
    }

    private func scheduleReconnect() {
        guard wantsConnection else { return }
        pingTimer?.invalidate()
        reconnectTask?.cancel()
        reconnectAttempts += 1
        // Cap backoff so a flapping socket cannot stack reconnect Tasks forever.
        let cappedAttempt = min(reconnectAttempts, 6)
        let delay = min(MarketWebSocketLimits.maxReconnectDelaySeconds, pow(2.0, Double(cappedAttempt)))
        let generation = receiveGeneration
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.wantsConnection else { return }
            guard generation == self.receiveGeneration else { return }
            self.open()
        }
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        self.isConnected = connected
        onStatusChange?(connected)
    }
}
