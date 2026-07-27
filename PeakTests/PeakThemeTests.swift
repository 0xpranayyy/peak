import XCTest
import SwiftUI
import UIKit
@testable import Peak

/// The accent themes.
///
/// The type's doc comment claims each ramp is "tuned for both appearances" and
/// that curation exists so users cannot pick an unreadable accent. That is a
/// promise about contrast, so it is checked here rather than left as a comment.
final class PeakThemeTests: XCTestCase {

    /// WCAG relative luminance.
    private func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: - Contrast

    /// CTA text is chosen from the fill, so what must hold is that the *chosen*
    /// colour is readable on every theme in both appearances.
    ///
    /// Asserting white specifically is what this test did first, and it failed
    /// on all six themes — including the original teal, at 1.83:1. That was a
    /// real defect already shipping, and the reason `PeakContrast` exists.
    func testCTATextIsReadableOnEveryThemeInBothAppearances() {
        for theme in PeakTheme.allCases {
            for (name, fill) in [("light", theme.ramp.midLight), ("dark", theme.ramp.midDark)] {
                let chosen = UIColor(PeakContrast.readableText(on: fill))
                let ratio = contrast(chosen, fill)
                XCTAssertGreaterThanOrEqual(
                    ratio, PeakContrast.minimumRatio,
                    "\(theme.rawValue) \(name) mid gives CTA text only \(String(format: "%.2f", ratio)):1"
                )
            }
        }
    }

    /// White is kept wherever it clears the floor, so adding themes never
    /// silently restyles a button that was already fine.
    func testWhiteIsRetainedWhereItIsAdequate() {
        XCTAssertEqual(
            PeakContrast.readableText(on: PeakTheme.teal.ramp.midLight),
            Color(uiColor: PeakContrast.onDark),
            "light teal reads at 4.08:1 with white and must not be flipped to dark text"
        )
    }

    /// The helper must actually switch, not just always return one colour —
    /// otherwise it would pass the test above by accident on a narrow palette.
    func testReadableTextPicksLightOnDarkFillsAndDarkOnLightFills() {
        let onNearBlack = PeakContrast.readableText(on: UIColor(white: 0.05, alpha: 1))
        let onNearWhite = PeakContrast.readableText(on: UIColor(white: 0.95, alpha: 1))
        XCTAssertNotEqual(onNearBlack, onNearWhite, "the helper never switches")
        XCTAssertEqual(onNearBlack, Color(uiColor: PeakContrast.onDark))
        XCTAssertEqual(onNearWhite, Color(uiColor: PeakContrast.onLight))
    }

    /// Pinning the specific case that started this: the original dark teal,
    /// which shipped with white text at 1.83:1.
    func testOriginalDarkTealNoLongerUsesWhiteText() {
        let fill = PeakTheme.teal.ramp.midDark
        XCTAssertLessThan(contrast(.white, fill), 2.0, "premise: white was unreadable here")
        XCTAssertEqual(
            PeakContrast.readableText(on: fill),
            Color(uiColor: PeakContrast.onLight),
            "must flip to dark text"
        )
        XCTAssertGreaterThanOrEqual(
            contrast(UIColor(PeakContrast.readableText(on: fill)), fill), 4.5
        )
    }

    /// The dark-mode step must be lighter than the light-mode step. Getting the
    /// pair backwards yields a theme that is legible in one appearance and mud
    /// in the other — the exact failure the Light/Dark pairing exists to avoid.
    func testDarkStepsAreLighterThanLightSteps() {
        for theme in PeakTheme.allCases {
            let r = theme.ramp
            for (name, pair) in [
                ("deep", (r.deepLight, r.deepDark)),
                ("mid", (r.midLight, r.midDark)),
                ("soft", (r.softLight, r.softDark)),
                ("mist", (r.mistLight, r.mistDark)),
            ] {
                XCTAssertGreaterThan(
                    luminance(pair.1), luminance(pair.0),
                    "\(theme.rawValue).\(name) dark variant is not lighter than its light variant"
                )
            }
        }
    }

    /// A ramp should darken from mist to deep in light mode; a shuffled ramp
    /// still "works" but flattens every gradient built from it.
    func testRampIsOrderedWithinEachAppearance() {
        for theme in PeakTheme.allCases {
            let r = theme.ramp
            XCTAssertGreaterThan(luminance(r.mistLight), luminance(r.deepLight), "\(theme.rawValue) light")
            XCTAssertGreaterThan(luminance(r.mistDark), luminance(r.deepDark), "\(theme.rawValue) dark")
        }
    }

    // MARK: - Identity and caching

    /// Colours are cached per theme. If a fresh `PeakBrandColors` were built on
    /// every access, SwiftUI would see a structurally new value on each render
    /// and lose its ability to skip unchanged views.
    func testColoursAreStableAcrossAccesses() {
        for theme in PeakTheme.allCases {
            XCTAssertEqual(theme.colors, theme.colors, "\(theme.rawValue) colours are not stable")
        }
    }

    func testThemesAreVisuallyDistinct() {
        let mids = PeakTheme.allCases.map { $0.colors.mid }
        for i in mids.indices {
            for j in mids.indices where j > i {
                XCTAssertNotEqual(
                    mids[i], mids[j],
                    "\(PeakTheme.allCases[i].rawValue) and \(PeakTheme.allCases[j].rawValue) look the same"
                )
            }
        }
    }

    // MARK: - Persistence contract

    /// Raw values are written to UserDefaults. Renaming a case silently resets
    /// everyone's saved theme, so the strings are pinned.
    func testRawValuesAreStable() {
        XCTAssertEqual(
            Set(PeakTheme.allCases.map(\.rawValue)),
            ["teal", "courtGreen", "indigo", "ember", "graphite", "violet"]
        )
    }

    func testEveryThemeRoundTripsThroughItsRawValue() {
        for theme in PeakTheme.allCases {
            XCTAssertEqual(PeakTheme(rawValue: theme.rawValue), theme)
        }
    }

    func testUnknownStoredValueIsRejectedSoTheStoreCanFallBack() {
        XCTAssertNil(PeakTheme(rawValue: "chartreuse"))
    }

    func testEveryThemeHasATitle() {
        for theme in PeakTheme.allCases {
            XCTAssertFalse(theme.title.isEmpty)
            XCTAssertNotEqual(theme.title, theme.rawValue, "\(theme.rawValue) needs a human title")
        }
    }

    // MARK: - Environment default

    /// Anything rendering outside the app's environment (widgets, previews)
    /// falls back to the default rather than to an unset colour.
    func testEnvironmentDefaultIsTeal() {
        XCTAssertEqual(EnvironmentValues().peakBrand, PeakTheme.teal.colors)
    }

    /// The legacy `PeakBrand` constants must stay pinned to teal — they are the
    /// non-themeable fallback, and quietly re-pointing them at the active theme
    /// would reintroduce the global mutable state this replaced.
    func testLegacyBrandConstantsMatchTeal() {
        XCTAssertEqual(PeakBrand.mid, PeakTheme.teal.colors.mid)
        XCTAssertEqual(PeakBrand.deep, PeakTheme.teal.colors.deep)
    }
}
