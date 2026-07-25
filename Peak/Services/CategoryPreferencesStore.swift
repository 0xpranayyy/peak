import Foundation
import Combine

@MainActor
final class CategoryPreferencesStore: ObservableObject {
    static let shared = CategoryPreferencesStore()

    private let interestsKey = "peak.categories.interests"

    @Published private(set) var interestedSlugs: [String]
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "peak.onboarding.completed")
        }
    }

    init() {
        interestedSlugs = UserDefaults.standard.stringArray(forKey: interestsKey) ?? []
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "peak.onboarding.completed")
    }

    var interestedCategories: [MarketCategory] {
        let map = Dictionary(uniqueKeysWithValues: MarketCategory.allCases.map { ($0.slug, $0) })
        return interestedSlugs.compactMap { map[$0] }
    }

    /// Browse chip order: user interests first, then the rest of the curated set.
    var orderedCategories: [MarketCategory] {
        let preferred = interestedCategories
        let rest = MarketCategory.allCases.filter { cat in
            !preferred.contains(cat)
        }
        return preferred + rest
    }

    func setInterests(_ categories: [MarketCategory]) {
        interestedSlugs = categories.map(\.slug)
        UserDefaults.standard.set(interestedSlugs, forKey: interestsKey)
        objectWillChange.send()
    }

    func toggleInterest(_ category: MarketCategory) {
        var current = Set(interestedSlugs)
        if current.contains(category.slug) {
            current.remove(category.slug)
        } else {
            current.insert(category.slug)
        }
        interestedSlugs = MarketCategory.allCases
            .map(\.slug)
            .filter { current.contains($0) }
        UserDefaults.standard.set(interestedSlugs, forKey: interestsKey)
        objectWillChange.send()
    }

    func isInterested(_ category: MarketCategory) -> Bool {
        interestedSlugs.contains(category.slug)
    }

    func completeOnboarding(interests: [MarketCategory]) {
        setInterests(interests)
        hasCompletedOnboarding = true
    }
}
