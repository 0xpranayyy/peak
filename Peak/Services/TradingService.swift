import Foundation

struct OpenOrder: Identifiable, Hashable, Sendable {
    let id: String
    let tokenID: String
    let market: String?
    let side: String
    let price: Double
    let originalSize: Double
    let sizeMatched: Double
    let status: String?

    var remaining: Double { max(0, originalSize - sizeMatched) }
}

struct TradingPathFlags: Sendable {
    var path: String?
    var signer: String?
    var accountWallet: String?
    var walletTypeName: String?
    var syncReady: Bool?
    var needsDeploy: Bool?
    var builderConfigured: Bool?
    var relayerConfigured: Bool?
    var needsImport: Bool?

    func asServerDict() -> [String: Any] {
        var out: [String: Any] = [:]
        if let path { out["path"] = path }
        if let signer { out["signer"] = signer }
        if let accountWallet { out["accountWallet"] = accountWallet }
        if let walletTypeName { out["walletTypeName"] = walletTypeName }
        if let syncReady { out["syncReady"] = syncReady }
        if let needsDeploy { out["needsDeploy"] = needsDeploy }
        if let builderConfigured { out["builderConfigured"] = builderConfigured }
        if let relayerConfigured { out["relayerConfigured"] = relayerConfigured }
        if let needsImport { out["needsImport"] = needsImport }
        return out
    }

    static func fromPortfolioRoot(_ root: [String: Any]) -> TradingPathFlags {
        TradingPathFlags(
            path: root["path"] as? String,
            signer: root["signer"] as? String,
            accountWallet: root["accountWallet"] as? String ?? root["funder"] as? String,
            walletTypeName: root["walletTypeName"] as? String,
            syncReady: root["syncReady"] as? Bool ?? root["ready"] as? Bool,
            needsDeploy: root["needsDeploy"] as? Bool,
            builderConfigured: root["builderConfigured"] as? Bool,
            relayerConfigured: root["relayerConfigured"] as? Bool,
            needsImport: root["needsImport"] as? Bool
                ?? ((root["cashErrorCode"] as? String)?.lowercased() == "import_wallet_required")
        )
    }
}

struct TradingPortfolioSnapshot: Sendable {
    let funder: String?
    let cash: Double?
    let cashError: String?
    let cashErrorCode: String?
    let needsImport: Bool
    let totalValue: Double?
    let positions: [PortfolioPosition]
    let activity: [PortfolioActivity]
    let openOrders: [OpenOrder]
    let pathFlags: TradingPathFlags
}

struct DepositAddressResult: @unchecked Sendable {
    let address: String?
    let raw: [String: Any]
}

/// Phase 2+ trading surface (proxy-backed).
protocol TradingService: Sendable {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double,
        amount: Double?,
        negRisk: Bool?,
        orderType: String
    ) async throws -> TradeResult

    func fetchOpenOrders() async throws -> [OpenOrder]
    func cancelOrder(id: String) async throws
    func fetchTradingPortfolio() async throws -> TradingPortfolioSnapshot
    func requestDepositAddress(chain: String, token: String) async throws -> DepositAddressResult
}

enum TradeSide: String, Sendable {
    case buy
    case sell
}

struct TradeResult: Sendable {
    let orderID: String
    let status: String
    let success: Bool
}

enum TradingError: LocalizedError, Sendable {
    case notConfigured
    case notAvailable
    case invalidAmount
    case missingToken
    case marketClosed
    case builderNotReady
    case setupRequired
    case insufficientFunds(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sign in to trade."
        case .notAvailable:
            return "Trading isn’t available right now. Try again later."
        case .invalidAmount:
            return "Enter a valid USD amount and price."
        case .missingToken:
            return "This market can’t be traded right now."
        case .marketClosed:
            return "This market is closed or not accepting orders."
        case .setupRequired:
            return "Finish Set up trading under Account, then try again."
        case .builderNotReady:
            return "Your wallet isn’t ready yet. Try again in a moment."
        case .insufficientFunds(let message):
            return message
        case .server(let message):
            return message
        }
    }

    /// Map backend / CLOB copy into actionable user-facing errors.
    static func fromServerMessage(_ raw: String, code: String? = nil) -> TradingError {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let codeLower = (code ?? "").lowercased()

        if codeLower == "import_wallet_required"
            || lower.contains("import_wallet_required")
            || lower.contains("import the private key")
        {
            return .server(PeakUserCopy.importWalletRequired)
        }
        if codeLower == "wallet_auth_failed"
            || PeakUserCopy.isWalletAuthFailure(text)
            || (lower.contains("401") && lower.contains("authorization"))
        {
            return .server(PeakUserCopy.walletAuthFailed)
        }
        if codeLower == "sign_failed"
            || lower.contains("typed_data")
            || lower.contains("unrecognized_keys")
            || lower.contains("invalid_data")
            || (lower.contains("params") && lower.contains("required"))
        {
            return .server(PeakUserCopy.signFailed)
        }
        if codeLower == "approvals_failed" || lower.contains("trading approvals") {
            return .server(PeakUserCopy.approvalsNeeded)
        }
        if codeLower == "insufficient_funds"
            || codeLower == "insufficient_shares"
            || lower.contains("not enough balance")
            || lower.contains("insufficient funds")
            || lower.contains("balance / allowance")
            || lower.contains("not enough shares")
        {
            let fallback = PeakUserCopy.insufficientFunds
            return .insufficientFunds(text.isEmpty ? fallback : Self.sanitizeServerCopy(text, fallback: fallback))
        }
        if codeLower == "builder_not_ready" || lower.contains("builder credential") {
            return .builderNotReady
        }
        if codeLower == "setup_failed" || codeLower == "deploy_failed" {
            return .server(
                text.isEmpty
                    ? "Couldn’t finish wallet setup. Try again."
                    : Self.sanitizeServerCopy(text, fallback: "Couldn’t finish wallet setup. Try again.")
            )
        }
        if codeLower == "embedded_wallet_required" {
            return .server(
                Self.sanitizeServerCopy(
                    text,
                    fallback: "Peak needs a trading wallet. Sign in with email or Apple, then try I’m new again."
                )
            )
        }
        if codeLower == "no_fill" || lower.contains("no fill") || lower.contains("liquidity too thin") {
            return .server(
                text.isEmpty
                    ? "No fill at this price. Try a limit order or a smaller size."
                    : Self.sanitizeServerCopy(text, fallback: "No fill at this price. Try a limit order or a smaller size.")
            )
        }
        if codeLower == "setup_required"
            || lower.contains("trading/setup")
            || lower.contains("deposit wallet")
            || lower.contains("finish setup")
            || lower.contains("finish set up")
            || lower.contains("set up trading")
        {
            return .setupRequired
        }
        if codeLower == "market_closed" || lower.contains("not accepting") {
            return .marketClosed
        }
        if lower == "unauthorized" || codeLower == "unauthorized" {
            return .notConfigured
        }
        if codeLower == "invalid_order" || lower.contains("valid usd amount") {
            return .invalidAmount
        }
        if text.isEmpty {
            return .server("Couldn’t place order. Try again.")
        }
        return .server(sanitizeServerCopy(text, fallback: "Couldn’t place order. Try again."))
    }

    /// True when the server wants the user to import a matching PM private key.
    var isImportWalletRequired: Bool {
        switch self {
        case .server(let message):
            return PeakUserCopy.isImportWalletMessage(message)
        default:
            return false
        }
    }

    /// Strip infra jargon from server copy in Release; keep precise text in DEBUG.
    private static func sanitizeServerCopy(_ text: String, fallback: String) -> String {
        PeakUserCopy.sanitize(text, fallback: fallback)
    }
}

extension Notification.Name {
    /// Posted after a successful live order so Portfolio can refresh.
    static let peakTradingPortfolioShouldRefresh = Notification.Name("peak.trading.portfolioShouldRefresh")
    /// Switch root tab — `userInfo["tab"]` is a `PeakRootTab.rawValue` String.
    static let peakSelectRootTab = Notification.Name("peak.selectRootTab")
}

enum PeakRootTab: String, Hashable {
    case markets
    case search
    case portfolio
    case watchlist
    case settings

    static func select(_ tab: PeakRootTab) {
        NotificationCenter.default.post(
            name: .peakSelectRootTab,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )
    }
}

struct StubTradingService: TradingService {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double,
        amount: Double?,
        negRisk: Bool?,
        orderType: String
    ) async throws -> TradeResult {
        throw TradingError.notConfigured
    }

    func fetchOpenOrders() async throws -> [OpenOrder] { throw TradingError.notConfigured }
    func cancelOrder(id: String) async throws { throw TradingError.notConfigured }
    func fetchTradingPortfolio() async throws -> TradingPortfolioSnapshot { throw TradingError.notConfigured }
    func requestDepositAddress(chain: String, token: String) async throws -> DepositAddressResult {
        throw TradingError.notConfigured
    }
}

/// Posts to the Peak Node proxy (`backend/`). Private keys never leave the proxy.
struct RemoteTradingService: TradingService, @unchecked Sendable {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double,
        amount: Double?,
        negRisk: Bool?,
        orderType: String
    ) async throws -> TradeResult {
        guard !tokenID.isEmpty, size > 0, price > 0, price < 1 else {
            throw TradingError.invalidAmount
        }

        var body: [String: Any] = [
            "tokenID": tokenID,
            "price": (price * 1000).rounded() / 1000,
            "size": (size * 100).rounded() / 100,
            "side": side == .buy ? "BUY" : "SELL",
            "orderType": orderType,
        ]
        if let amount, amount > 0 {
            // Market BUY: USD to spend. Market SELL: shares to sell.
            body["amount"] = (amount * 100).rounded() / 100
        }
        if let negRisk {
            body["negRisk"] = negRisk
        }

        // Submit from the device, not the backend.
        //
        // CLOB evaluates its geoblock against the IP the order arrives from. Our
        // backend is hosted in a restricted region, so posting from there gets
        // every order refused regardless of where the user actually is. The
        // backend still builds and signs — keys never leave it — but this device
        // performs the final POST so eligibility is judged per user.
        do {
            let prepared = try await TradingProxyClient.prepareOrder(jsonBody: body)
            let root = try await TradingProxyClient.submitPreparedOrder(prepared)
            return try Self.parseTradeResult(root)
        } catch let error as TradingError {
            // Only fall back when the backend lacks the endpoint. A rejection
            // (funds, region, closed market) is a real answer and must surface
            // as-is rather than being retried down the path that fails for
            // everyone.
            guard Self.isMissingPrepareEndpoint(error) else { throw error }
            let root = try await TradingProxyClient.jsonObject(path: "orders", method: "POST", jsonBody: body)
            return try Self.parseTradeResult(root)
        }
    }

    func fetchOpenOrders() async throws -> [OpenOrder] {
        let data = try await TradingProxyClient.request(path: "orders")
        let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let rows = root["open"] as? [[String: Any]] ?? []
        return rows.compactMap(Self.mapOpenOrder)
    }

    func cancelOrder(id: String) async throws {
        _ = try await TradingProxyClient.request(path: "orders/\(id)", method: "DELETE")
    }

    func fetchTradingPortfolio() async throws -> TradingPortfolioSnapshot {
        async let portfolioData = TradingProxyClient.request(path: "portfolio")
        async let activityData = TradingProxyClient.request(
            path: "activity",
            query: [.init(name: "limit", value: "20")]
        )
        async let ordersData = TradingProxyClient.request(path: "orders")

        let portfolioRoot = (try? JSONSerialization.jsonObject(with: try await portfolioData) as? [String: Any]) ?? [:]
        let activityRows = (try? JSONSerialization.jsonObject(with: try await activityData) as? [[String: Any]]) ?? []
        let ordersRoot = (try? JSONSerialization.jsonObject(with: try await ordersData) as? [String: Any]) ?? [:]

        let positionRows = portfolioRoot["positions"] as? [[String: Any]] ?? []
        let positions: [PortfolioPosition] = positionRows.compactMap { row in
            guard let data = try? JSONSerialization.data(withJSONObject: row),
                  let dto = try? JSONDecoder().decode(DataAPI.PositionDTO.self, from: data) else {
                return nil
            }
            return dto.asPosition()
        }

        let activity: [PortfolioActivity] = activityRows.compactMap { row in
            guard let data = try? JSONSerialization.data(withJSONObject: row),
                  let dto = try? JSONDecoder().decode(DataAPI.ActivityDTO.self, from: data) else {
                return nil
            }
            return dto.asActivity()
        }

        let open = (ordersRoot["open"] as? [[String: Any]] ?? []).compactMap(Self.mapOpenOrder)

        var cash: Double?
        if let cashUSD = Self.double(portfolioRoot["cashUSD"]) {
            cash = cashUSD
        } else if let balance = portfolioRoot["balance"] as? [String: Any] {
            cash = Self.double(balance["balance"]).map { raw in
                raw > 100_000 ? raw / 1_000_000 : raw
            }
        }

        var totalValue: Double?
        if let value = portfolioRoot["value"] as? [String: Any] {
            totalValue = Self.double(value["value"])
        } else if let arr = portfolioRoot["value"] as? [[String: Any]], let first = arr.first {
            totalValue = Self.double(first["value"])
        }

        return TradingPortfolioSnapshot(
            funder: portfolioRoot["funder"] as? String,
            cash: cash,
            cashError: portfolioRoot["cashError"] as? String,
            cashErrorCode: portfolioRoot["cashErrorCode"] as? String,
            needsImport: (portfolioRoot["needsImport"] as? Bool)
                ?? ((portfolioRoot["cashErrorCode"] as? String)?.lowercased() == "import_wallet_required"),
            totalValue: totalValue,
            positions: positions,
            activity: activity,
            openOrders: open,
            pathFlags: TradingPathFlags.fromPortfolioRoot(portfolioRoot)
        )
    }

    func requestDepositAddress(chain: String, token: String) async throws -> DepositAddressResult {
        let root = try await TradingProxyClient.jsonObject(
            path: "deposit-address",
            method: "POST",
            jsonBody: [
                "chain": chain,
                "token": token,
            ]
        )
        let address = Self.pickDepositAddress(from: root, chain: chain)
        return DepositAddressResult(address: address, raw: root)
    }

    /// Flatten Bridge `{ address: { evm, svm, … } }` or string fields.
    private static func pickDepositAddress(from root: [String: Any], chain: String) -> String? {
        if let s = root["depositAddress"] as? String, !s.isEmpty { return s }
        if let s = root["address"] as? String, !s.isEmpty { return s }
        if let s = root["funder"] as? String, !s.isEmpty { return s }
        if let s = root["accountWallet"] as? String, !s.isEmpty { return s }

        if let obj = root["address"] as? [String: Any], let nested = addressFromBridgeObject(obj, chain: chain) {
            return nested
        }
        if let obj = root["depositAddress"] as? [String: Any], let nested = addressFromBridgeObject(obj, chain: chain) {
            return nested
        }
        // Some Bridge payloads nest under `addresses` / `data`.
        if let obj = root["addresses"] as? [String: Any], let nested = addressFromBridgeObject(obj, chain: chain) {
            return nested
        }
        if let data = root["data"] as? [String: Any] {
            return pickDepositAddress(from: data, chain: chain)
        }
        return nil
    }

    private static func addressFromBridgeObject(_ obj: [String: Any], chain: String) -> String? {
        let c = chain.lowercased()
        if c == "solana" || c == "svm", let s = obj["svm"] as? String, !s.isEmpty { return s }
        if c == "bitcoin" || c == "btc", let s = obj["btc"] as? String, !s.isEmpty { return s }
        if c == "tron" || c == "tvm", let s = obj["tvm"] as? String, !s.isEmpty { return s }
        if let s = obj["evm"] as? String, !s.isEmpty { return s }
        if let s = obj["address"] as? String, !s.isEmpty { return s }
        if let s = obj["depositAddress"] as? String, !s.isEmpty { return s }
        return nil
    }

    /// True only when the backend predates `/orders/prepare`.
    ///
    /// Kept narrow on purpose: treating any failure as "endpoint missing" would
    /// quietly resend rejected orders through the backend path, which is exactly
    /// the path that fails for everyone.
    private static func isMissingPrepareEndpoint(_ error: TradingError) -> Bool {
        guard case .server(let message) = error else { return false }
        let lower = message.lowercased()
        return lower.contains("not found") || lower.contains("404")
    }

    private static func parseTradeResult(_ root: [String: Any]) throws -> TradeResult {
        let orderID = (root["orderID"] as? String) ?? (root["id"] as? String) ?? ""
        let status = (root["status"] as? String) ?? ""
        let errorText =
            (root["errorMsg"] as? String)
            ?? (root["error"] as? String)
            ?? ""
        let code = root["code"] as? String
        let successFlag = root["success"] as? Bool

        if let successFlag, !successFlag {
            throw TradingError.fromServerMessage(
                errorText.isEmpty ? (status.isEmpty ? "Order rejected" : status) : errorText,
                code: code
            )
        }
        if !errorText.isEmpty, orderID.isEmpty {
            throw TradingError.fromServerMessage(errorText, code: code)
        }
        // CLOB success responses include success:true; never invent success from a bare status.
        let success = successFlag ?? (!orderID.isEmpty && !status.lowercased().contains("error"))
        if !success {
            throw TradingError.fromServerMessage(
                errorText.isEmpty ? (status.isEmpty ? "Order failed" : status) : errorText,
                code: code
            )
        }
        return TradeResult(
            orderID: orderID.isEmpty ? (status.isEmpty ? "submitted" : status) : orderID,
            status: status.isEmpty ? "submitted" : status,
            success: true
        )
    }

    private static func mapOpenOrder(_ row: [String: Any]) -> OpenOrder? {
        let id = (row["id"] as? String) ?? (row["orderID"] as? String) ?? (row["order_id"] as? String)
        guard let id else { return nil }
        return OpenOrder(
            id: id,
            tokenID: (row["asset_id"] as? String) ?? (row["tokenID"] as? String) ?? "",
            market: row["market"] as? String,
            side: ((row["side"] as? String) ?? "BUY").uppercased(),
            price: double(row["price"]) ?? 0,
            originalSize: double(row["original_size"]) ?? double(row["size"]) ?? 0,
            sizeMatched: double(row["size_matched"]) ?? double(row["matched"]) ?? 0,
            status: row["status"] as? String
        )
    }

    private static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
