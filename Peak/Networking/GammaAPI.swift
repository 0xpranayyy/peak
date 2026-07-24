import Foundation

enum MarketSort: String, CaseIterable, Identifiable, Sendable {
    case trending
    case volume
    case newest
    case endingSoon
    case liquidity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending: return "Trending"
        case .volume: return "Volume"
        case .newest: return "New"
        case .endingSoon: return "Ending"
        case .liquidity: return "Liquidity"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .trending:
            [.init(name: "order", value: "volume24hr"), .init(name: "ascending", value: "false")]
        case .volume:
            [.init(name: "order", value: "volume"), .init(name: "ascending", value: "false")]
        case .newest:
            [.init(name: "order", value: "startDate"), .init(name: "ascending", value: "false")]
        case .endingSoon:
            [.init(name: "order", value: "endDate"), .init(name: "ascending", value: "true")]
        case .liquidity:
            [.init(name: "order", value: "liquidity"), .init(name: "ascending", value: "false")]
        }
    }
}

enum GammaAPI {
    // MARK: - DTOs

    struct GammaTagDTO: Decodable {
        let id: String?
        let label: String?
        let name: String?
        let slug: String?

        var asTag: MarketTag? {
            let resolvedID = id ?? slug ?? label ?? name
            let resolvedLabel = label ?? name ?? slug
            guard let resolvedID, let resolvedLabel else { return nil }
            return MarketTag(id: resolvedID, label: resolvedLabel, slug: slug)
        }
    }

    struct GammaMarketDTO: Decodable {
        let id: String?
        let question: String?
        let slug: String?
        let conditionId: String?
        let outcomes: FlexibleStringArray?
        let outcomePrices: FlexibleStringArray?
        let clobTokenIds: FlexibleStringArray?
        let volume: FlexibleDouble?
        let volumeNum: FlexibleDouble?
        let volume24hr: FlexibleDouble?
        let liquidity: FlexibleDouble?
        let liquidityNum: FlexibleDouble?
        let endDate: String?
        let negRisk: Bool?
        let active: Bool?
        let closed: Bool?
        let image: String?
        let icon: String?
        let events: [GammaEventLiteDTO]?

        func asMarket(eventId: String? = nil, eventTitle: String? = nil) -> Market? {
            guard let id, let question else { return nil }
            let prices = outcomePrices?.values.compactMap(Double.init) ?? []
            let tokens = clobTokenIds?.values ?? []
            let outcomes = self.outcomes?.values ?? ["Yes", "No"]
            let lite = events?.first
            return Market(
                id: id,
                question: question,
                slug: slug,
                conditionId: conditionId,
                outcomes: outcomes.isEmpty ? ["Yes", "No"] : outcomes,
                outcomePrices: prices.isEmpty ? [0.5, 0.5] : prices,
                clobTokenIds: tokens,
                volume: volume?.value ?? volumeNum?.value ?? 0,
                volume24hr: volume24hr?.value ?? 0,
                liquidity: liquidity?.value ?? liquidityNum?.value ?? 0,
                endDate: endDate.flatMap(Self.parseDate),
                negRisk: negRisk ?? false,
                active: active ?? true,
                closed: closed ?? false,
                eventId: eventId ?? lite?.id,
                eventTitle: eventTitle ?? lite?.title,
                imageURL: (image ?? icon).flatMap(URL.init(string:))
            )
        }

        private static func parseDate(_ raw: String) -> Date? {
            ISO8601DateFormatter.peakFractional.date(from: raw)
                ?? ISO8601DateFormatter.peak.date(from: raw)
        }
    }

    struct GammaEventLiteDTO: Decodable {
        let id: String?
        let title: String?
        let slug: String?
    }

    struct GammaEventDTO: Decodable {
        let id: String?
        let slug: String?
        let title: String?
        let description: String?
        let image: String?
        let icon: String?
        let endDate: String?
        let volume: FlexibleDouble?
        let volume24hr: FlexibleDouble?
        let liquidity: FlexibleDouble?
        let tags: [GammaTagDTO]?
        let markets: [GammaMarketDTO]?

        func asEvent() -> PeakEvent? {
            guard let id, let title else { return nil }
            let mappedMarkets = (markets ?? []).compactMap { $0.asMarket(eventId: id, eventTitle: title) }
            return PeakEvent(
                id: id,
                slug: slug,
                title: title,
                description: description,
                imageURL: (image ?? icon).flatMap(URL.init(string:)),
                endDate: endDate.flatMap {
                    ISO8601DateFormatter.peakFractional.date(from: $0)
                        ?? ISO8601DateFormatter.peak.date(from: $0)
                },
                volume: volume?.value ?? 0,
                volume24hr: volume24hr?.value ?? 0,
                liquidity: liquidity?.value ?? 0,
                tags: (tags ?? []).compactMap(\.asTag),
                markets: mappedMarkets
            )
        }
    }

    // Flexible wrappers for Gamma's mixed types

    struct FlexibleStringArray: Decodable {
        let values: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let arr = try? container.decode([String].self) {
                values = arr
            } else if let s = try? container.decode(String.self) {
                values = JSONStringDecoding.stringArray(from: s)
            } else if let arr = try? container.decode([FlexibleScalar].self) {
                values = arr.map(\.stringValue)
            } else {
                values = []
            }
        }
    }

    struct FlexibleDouble: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let d = try? container.decode(Double.self) {
                value = d
            } else if let i = try? container.decode(Int.self) {
                value = Double(i)
            } else if let s = try? container.decode(String.self), let d = Double(s) {
                value = d
            } else {
                value = 0
            }
        }
    }

    struct FlexibleScalar: Decodable {
        let stringValue: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                stringValue = s
            } else if let i = try? container.decode(Int.self) {
                stringValue = String(i)
            } else if let d = try? container.decode(Double.self) {
                stringValue = String(d)
            } else {
                stringValue = ""
            }
        }
    }

    // MARK: - Endpoints

    static func fetchTags(limit: Int = 40) async throws -> [MarketTag] {
        let url = PeakAPIBase.gamma.appendingPathComponent("tags")
        let raw: [GammaTagDTO] = try await APIClient.shared.get(
            url,
            query: [
                .init(name: "limit", value: String(limit)),
                .init(name: "offset", value: "0"),
            ]
        )
        var seen = Set<String>()
        return raw.compactMap(\.asTag).filter { seen.insert($0.id).inserted }
    }

    static func fetchEvents(
        limit: Int = 20,
        offset: Int = 0,
        sort: MarketSort = .trending,
        tagSlug: String? = nil
    ) async throws -> [PeakEvent] {
        var query: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "active", value: "true"),
            .init(name: "closed", value: "false"),
        ] + sort.queryItems
        if let tagSlug, !tagSlug.isEmpty {
            query.append(.init(name: "tag_slug", value: tagSlug))
        }
        let url = PeakAPIBase.gamma.appendingPathComponent("events")
        let raw: [GammaEventDTO] = try await APIClient.shared.get(url, query: query)
        return raw.compactMap { $0.asEvent() }.filter { !$0.markets.isEmpty }
    }

    static func fetchEvent(id: String) async throws -> PeakEvent {
        let url = PeakAPIBase.gamma.appendingPathComponent("events").appendingPathComponent(id)
        let raw: GammaEventDTO = try await APIClient.shared.get(url)
        guard let event = raw.asEvent() else { throw APIError.emptyResponse }
        return event
    }

    static func fetchMarkets(
        limit: Int = 40,
        offset: Int = 0,
        sort: MarketSort = .trending
    ) async throws -> [Market] {
        let url = PeakAPIBase.gamma.appendingPathComponent("markets")
        let query: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "active", value: "true"),
            .init(name: "closed", value: "false"),
        ] + sort.queryItems
        let raw: [GammaMarketDTO] = try await APIClient.shared.get(url, query: query)
        return raw.compactMap { $0.asMarket() }
    }

    struct SearchResult: Sendable {
        var events: [PeakEvent]
        var markets: [Market]
    }

    static func search(_ query: String, limitPerType: Int = 20) async throws -> SearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchResult(events: [], markets: []) }

        let url = PeakAPIBase.gamma.appendingPathComponent("public-search")
        let data = try await APIClient.shared.getData(
            url,
            query: [
                .init(name: "q", value: trimmed),
                .init(name: "limit_per_type", value: String(limitPerType)),
                .init(name: "events_status", value: "active"),
            ]
        )

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SearchResult(events: [], markets: [])
        }

        let eventRows = root["events"] as? [[String: Any]] ?? []
        let marketRows = root["markets"] as? [[String: Any]] ?? []

        let events: [PeakEvent] = eventRows.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let dto = try? JSONDecoder().decode(GammaEventDTO.self, from: data) else { return nil }
            return dto.asEvent()
        }

        var markets: [Market] = marketRows.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let dto = try? JSONDecoder().decode(GammaMarketDTO.self, from: data) else { return nil }
            return dto.asMarket()
        }

        for event in events {
            markets.append(contentsOf: event.markets)
        }

        var seen = Set<String>()
        let uniqueMarkets = markets.filter { seen.insert($0.id).inserted }
        return SearchResult(events: events, markets: uniqueMarkets)
    }
}
