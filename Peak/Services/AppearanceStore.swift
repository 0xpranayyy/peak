import SwiftUI
import Combine

/// User-facing appearance preference — System follows iOS Light/Dark.
enum PeakAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` means follow the system appearance.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    private let key = "peak.appearance"
    private let themeKey = "peak.theme"

    @Published var preference: PeakAppearance {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: key)
        }
    }

    /// Accent theme. Kept here rather than in its own store so there is one
    /// source of truth for "how the app looks" and one object to observe.
    @Published var theme: PeakTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
        }
    }

    /// What the root injects into the environment.
    var brand: PeakBrandColors { theme.colors }

    init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let value = PeakAppearance(rawValue: raw) {
            preference = value
        } else {
            preference = .system
        }

        theme = UserDefaults.standard.string(forKey: themeKey)
            .flatMap(PeakTheme.init(rawValue:)) ?? .teal
    }
}
