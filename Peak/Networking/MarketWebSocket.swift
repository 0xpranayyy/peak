import Foundation

/// Live prices via Polymarket's public CLOB Market WebSocket channel.
/// Subscribes with `assets_ids` and sends `PING` every 10 seconds.
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

    private var task: URLSessionWebSocketTask?
    private var assetIDs: [String] = []
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private var wantsConnection = false
    private var reconnectTask: Task<Void, Never>?
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
        task?.cancel(with: .normalClosure, reason: nil)
        let t = URLSession.shared.webSocketTask(with: Self.url)
        task = t
        t.resume()
        subscribe()
        receiveLoop()
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

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handle(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handle(text)
                        }
                    @unknown default:
                        break
                    }
                    if self.wantsConnection {
                        self.receiveLoop()
                    }
                case .failure:
                    self.setConnected(false)
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard text != "PONG", let data = text.data(using: .utf8) else { return }
        let root = try? JSONSerialization.jsonObject(with: data)
        let events: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            events = arr
        } else if let obj = root as? [String: Any] {
            events = [obj]
        } else {
            return
        }
        for event in events {
            process(event)
        }
    }

    private func process(_ event: [String: Any]) {
        let type = (event["event_type"] as? String ?? event["type"] as? String ?? "").lowercased()
        switch type {
        case "price_change":
            // `price` on each change is the *level affected*, not the market mid.
            // Prefer best_bid / best_ask for display quotes.
            if let nested = event["price_changes"] as? [[String: Any]] {
                for change in nested { emitQuote(change) }
            } else if event["asset_id"] != nil {
                emitQuote(event)
            }
        case "last_trade_price":
            emitLastTrade(event)
        case "best_bid_ask":
            emitQuote(event)
        case "book":
            if let asset = event["asset_id"] as? String {
                let bids = parseLevels(event["bids"], side: .bid)
                    .sorted { $0.price > $1.price }
                let asks = parseLevels(event["asks"], side: .ask)
                    .sorted { $0.price < $1.price }
                if !bids.isEmpty || !asks.isEmpty {
                    onBook?(asset, OrderBook(
                        bids: Array(bids.prefix(12)),
                        asks: Array(asks.prefix(12))
                    ))
                }
                if let bestBid = bids.map(\.price).max(),
                   let bestAsk = asks.map(\.price).min() {
                    onTopOfBook?(asset, bestBid, bestAsk)
                    onPrice?(asset, (bestBid + bestAsk) / 2, .quote)
                }
            }
        default:
            break
        }
    }

    private func emitLastTrade(_ dict: [String: Any]) {
        guard let asset = dict["asset_id"] as? String,
              let p = Self.double(dict["price"]),
              p >= 0, p <= 1 else { return }
        onPrice?(asset, p, .lastTrade)
    }

    private func emitQuote(_ dict: [String: Any]) {
        guard let asset = dict["asset_id"] as? String else { return }
        let bid = Self.double(dict["best_bid"])
        let ask = Self.double(dict["best_ask"])
        if bid != nil || ask != nil {
            onTopOfBook?(asset, bid, ask)
        }
        if let bid, let ask, bid > 0, ask > 0 {
            onPrice?(asset, (bid + ask) / 2, .quote)
        }
        // Do not fall back to `price` — on price_change that field is the book level touched.
    }

    private func parseLevels(_ raw: Any?, side: OrderBookLevel.Side) -> [OrderBookLevel] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let price = Self.double(row["price"]),
                  let size = Self.double(row["size"]) else { return nil }
            return OrderBookLevel(price: price, size: size, side: side)
        }
    }

    private static func double(_ value: Any?) -> Double? {
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
        isConnected = connected
        onStatusChange?(connected)
    }
}
