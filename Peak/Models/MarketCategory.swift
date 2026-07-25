import Foundation

/// Curated browse taxonomy mapped to Polymarket Gamma `tag_slug` values.
enum MarketCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case politics
    case elections
    case crypto
    case sports
    case finance
    case tech
    case ai
    case culture
    case science
    case world

    var id: String { rawValue }

    var title: String {
        switch self {
        case .politics: return "Politics"
        case .elections: return "Elections"
        case .crypto: return "Crypto"
        case .sports: return "Sports"
        case .finance: return "Finance"
        case .tech: return "Tech"
        case .ai: return "AI"
        case .culture: return "Culture"
        case .science: return "Science"
        case .world: return "World"
        }
    }

    /// Primary Gamma slug used for `tag_slug` queries.
    var slug: String {
        switch self {
        case .politics: return "politics"
        case .elections: return "elections"
        case .crypto: return "crypto"
        case .sports: return "sports"
        case .finance: return "business"
        case .tech: return "tech"
        case .ai: return "ai"
        case .culture: return "culture"
        case .science: return "science"
        case .world: return "world"
        }
    }

    /// All slugs to try (primary first) until Gamma returns markets.
    var querySlugs: [String] {
        var seen = Set<String>()
        return ([slug] + alternateSlugs).filter { seen.insert($0).inserted }
    }

    /// Alternate slugs Gamma may use for the same idea.
    var alternateSlugs: [String] {
        switch self {
        case .politics: return ["us-politics", "geopolitics"]
        case .elections: return ["election", "us-election", "politics"]
        case .crypto: return ["bitcoin", "ethereum"]
        case .sports: return ["nba", "nfl", "soccer", "football"]
        case .finance: return ["finance", "economy", "fed"]
        case .culture: return ["pop-culture", "entertainment", "movies"]
        case .tech: return ["technology", "ai"]
        case .world: return ["geopolitics", "global", "international"]
        case .ai: return ["artificial-intelligence", "tech"]
        case .science: return ["climate", "space"]
        }
    }

    var systemImage: String {
        switch self {
        case .politics: return "building.columns"
        case .elections: return "checkmark.seal"
        case .crypto: return "bitcoinsign.circle"
        case .sports: return "sportscourt"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .tech: return "desktopcomputer"
        case .ai: return "cpu"
        case .culture: return "theatermasks"
        case .science: return "atom"
        case .world: return "globe.americas"
        }
    }

    var asTag: MarketTag {
        MarketTag(id: rawValue, label: title, slug: slug)
    }

    static func matching(tag: MarketTag) -> MarketCategory? {
        let needle = (tag.slug ?? tag.label).lowercased()
        return allCases.first { category in
            category.slug == needle
                || category.alternateSlugs.contains(needle)
                || category.title.lowercased() == needle
                || tag.label.lowercased() == category.title.lowercased()
        }
    }

    static func primaryLabel(for event: PeakEvent) -> String? {
        for tag in event.tags {
            if let category = matching(tag: tag) {
                return category.title
            }
        }
        return event.tags.first?.label
    }
}
