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

    @Published var preference: PeakAppearance {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: key)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let value = PeakAppearance(rawValue: raw) {
            preference = value
        } else {
            preference = .system
        }
    }
}
