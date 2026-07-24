import Foundation

enum DataAPI {
    struct PositionDTO: Decodable {
        let proxyWallet: String?
        let asset: String?
        let conditionId: String?
        let size: FlexibleDouble?
        let avgPrice: FlexibleDouble?
        let initialValue: FlexibleDouble?
        let currentValue: FlexibleDouble?
        let cashPnl: FlexibleDouble?
        let percentPnl: FlexibleDouble?
        let totalBought: FlexibleDouble?
        let realizedPnl: FlexibleDouble?
        let curPrice: FlexibleDouble?
        let title: String?
        let slug: String?
        let icon: String?
        let eventSlug: String?
        let outcome: String?
        let outcomeIndex: Int?
        let oppositeOutcome: String?
        let oppositeAsset: String?
        let endDate: String?
        let redeemable: Bool?
        let mergeable: Bool?

        struct FlexibleDouble: Decodable {
            let value: Double
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let d = try? c.decode(Double.self) { value = d }
                else if let s = try? c.decode(String.self), let d = Double(s) { value = d }
                else if let i = try? c.decode(Int.self) { value = Double(i) }
                else { value = 0 }
            }
        }

        func asPosition() -> PortfolioPosition? {
            let size = size?.value ?? 0
            guard size != 0 else { return nil }
            let id = [conditionId, asset, outcome, title]
                .compactMap { $0 }
                .joined(separator: "|")
            return PortfolioPosition(
                id: id.isEmpty ? UUID().uuidString : id,
                title: title ?? "Position",
                outcome: outcome ?? "—",
                size: size,
                avgPrice: avgPrice?.value ?? 0,
                currentPrice: curPrice?.value ?? 0,
                currentValue: currentValue?.value ?? 0,
                cashPnl: cashPnl?.value ?? 0,
                percentPnl: percentPnl?.value ?? 0,
                curPrice: curPrice?.value ?? 0,
                eventSlug: eventSlug ?? slug,
                conditionId: conditionId,
                asset: asset
            )
        }
    }

    static func fetchPositions(wallet: String) async throws -> [PortfolioPosition] {
        let normalized = wallet.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.hasPrefix("0x"), normalized.count == 42 else {
            return []
        }
        let url = PeakAPIBase.data.appendingPathComponent("positions")
        let rows: [PositionDTO] = try await APIClient.shared.get(
            url,
            query: [
                .init(name: "user", value: normalized),
                .init(name: "sizeThreshold", value: "0"),
            ]
        )
        return rows.compactMap { $0.asPosition() }
    }
}
