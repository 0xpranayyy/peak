import Foundation

/// Live prices via Polymarket's public CLOB Market WebSocket channel.
/// Subscribes with `assets_ids` and sends `PING` every 10 seconds.
@MainActor
final class MarketWebSocket {
    static let url = URL(string: "wss://ws-subscriptions-clob.polymarket.com/ws/market")!

    private var task: URLSessionWebSocketTask?
    private var assetIDs: [String] = []
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private(set) var isConnected = false

    var onPrice: ((String, Double) -> Void)?
    var onBook: ((String, OrderBook) -> Void)?
    var onStatusChange: ((Bool) -> Void)?

    func connect(assetIDs: [String]) {
        self.assetIDs = assetIDs.filter { !$0.isEmpty }
        open()
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        setConnected(false)
    }

    private func open() {
        guard !assetIDs.isEmpty else { return }
        task?.cancel(with: .normalClosure, reason: nil)
        let t = URLSession.shared.webSocketTask(with: Self.url)
        task = t
        t.resume()
        subscribe()
        receiveLoop()
        startPing()
    }

    private func subscribe() {
        let payload: [String: Any] = [
            "assets_ids": assetIDs,
            "type": "market",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { [weak self] error in
            Task { @MainActor in
                if error == nil {
                    self?.setConnected(true)
                    self?.reconnectAttempts = 0
                } else {
                    self?.scheduleReconnect()
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
                    self.receiveLoop()
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
            if let nested = event["price_changes"] as? [[String: Any]] {
                for change in nested { emitPrice(change) }
            } else if event["asset_id"] != nil {
                emitPrice(event)
                if let changes = event["changes"] as? [[String: Any]], let last = changes.last {
                    emitPrice(last, fallbackAsset: event["asset_id"] as? String)
                }
            }
        case "last_trade_price":
            emitPrice(event)
        case "book":
            if let asset = event["asset_id"] as? String {
                let bids = parseLevels(event["bids"], side: .bid)
                let asks = parseLevels(event["asks"], side: .ask)
                if !bids.isEmpty || !asks.isEmpty {
                    onBook?(asset, OrderBook(bids: bids, asks: asks))
                }
                if let bestBid = bids.map(\.price).max(),
                   let bestAsk = asks.map(\.price).min() {
                    onPrice?(asset, (bestBid + bestAsk) / 2)
                }
            }
        default:
            break
        }
    }

    private func emitPrice(_ dict: [String: Any], fallbackAsset: String? = nil) {
        guard let asset = (dict["asset_id"] as? String) ?? fallbackAsset,
              let p = price(from: dict) else { return }
        onPrice?(asset, p)
    }

    private func price(from dict: [String: Any]) -> Double? {
        if let p = Self.double(dict["price"]), p > 0, p < 1 { return p }
        if let bid = Self.double(dict["best_bid"]),
           let ask = Self.double(dict["best_ask"]),
           bid > 0, ask > 0 {
            return (bid + ask) / 2
        }
        return nil
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
                self?.task?.send(.string("PING")) { _ in }
            }
        }
    }

    private func scheduleReconnect() {
        pingTimer?.invalidate()
        reconnectAttempts += 1
        let delay = min(30.0, pow(2.0, Double(min(reconnectAttempts, 5))))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.open()
        }
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onStatusChange?(connected)
    }
}
