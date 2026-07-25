import Foundation

/// Live prices via Polymarket's public CLOB Market WebSocket channel.
/// Subscribes with `assets_ids` and sends `PING` every 10 seconds.
///
/// JSON is parsed off the main actor; only typed callbacks hop to MainActor.
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

    private var task: URLSessionWebSocketTask?
    private var assetIDs: [String] = []
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private var wantsConnection = false
    private var reconnectTask: Task<Void, Never>?
    private var receiveGeneration = 0
    private(set) var isConnected = false

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
        setConnected(false)
    }

    private func open() {
        guard wantsConnection, !assetIDs.isEmpty else { return }
        receiveGeneration += 1
        let generation = receiveGeneration
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

                Task { @MainActor [weak self] in
                    guard let self, generation == self.receiveGeneration, self.wantsConnection else { return }
                    if let text, text != "PONG" {
                        Task.detached(priority: .utility) { [weak self] in
                            let events = MarketWebSocket.parse(text)
                            guard !events.isEmpty else { return }
                            await MainActor.run { [weak self] in
                                self?.dispatch(events, generation: generation)
                            }
                        }
                    }
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

    private func dispatch(_ events: [ParsedEvent], generation: Int) {
        guard wantsConnection, generation == receiveGeneration else { return }
        for event in events {
            switch event {
            case let .lastTrade(asset, price):
                onPrice?(asset, price, .lastTrade)
            case let .quote(asset, bid, ask):
                if bid != nil || ask != nil {
                    onTopOfBook?(asset, bid, ask)
                }
                if let bid, let ask, bid > 0, ask > 0 {
                    onPrice?(asset, (bid + ask) / 2, .quote)
                }
            case let .book(asset, book, bestBid, bestAsk):
                onBook?(asset, book)
                if bestBid != nil || bestAsk != nil {
                    onTopOfBook?(asset, bestBid, bestAsk)
                }
                if let bestBid, let bestAsk, bestBid > 0, bestAsk > 0 {
                    onPrice?(asset, (bestBid + bestAsk) / 2, .quote)
                }
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
        parsed.reserveCapacity(events.count)
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
                        bids: Array(bids.prefix(12)),
                        asks: Array(asks.prefix(12))
                    )
                    let bestBid = bids.map(\.price).max()
                    let bestAsk = asks.map(\.price).min()
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
        let limited = rows.prefix(64)
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
        let delay = min(30.0, pow(2.0, Double(min(reconnectAttempts, 5))))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.wantsConnection else { return }
            self.open()
        }
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        self.isConnected = connected
        onStatusChange?(connected)
    }
}
