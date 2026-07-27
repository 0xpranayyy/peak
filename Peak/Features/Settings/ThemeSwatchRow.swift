import SwiftUI

/// Horizontal row of tappable accent swatches.
///
/// Each swatch previews the theme's `mid` — the tone that actually lands on
/// CTAs — rather than the darkest step, so what you tap is what you get.
struct ThemeSwatchRow: View {
    @Binding var selection: PeakTheme

    @Environment(\.colorScheme) private var colorScheme

    private let diameter: CGFloat = 34

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(PeakTheme.allCases) { theme in
                    Button {
                        // Safe to animate: the theme travels through the
                        // environment, so this is a colour change on the views
                        // that use a brand colour — not a structural rebuild.
                        withAnimation(PeakMotion.soft) {
                            selection = theme
                        }
                        PeakHaptics.selection()
                    } label: {
                        swatch(for: theme)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.title)
                    .accessibilityAddTraits(theme == selection ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        // Row is the control; the individual swatches carry the labels.
        .accessibilityElement(children: .contain)
    }

    private func swatch(for theme: PeakTheme) -> some View {
        let ramp = theme.ramp
        let fill = Color(uiColor: colorScheme == .dark ? ramp.midDark : ramp.midLight)
        let isSelected = theme == selection

        return Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .overlay {
                // Checkmark instead of ring-only: colour alone should never be
                // the sole indicator of state.
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        // Graphite and the dark-mode pastels are too light for a
                        // white tick to register.
                        .foregroundStyle(PeakContrast.readableText(on: UIColor(fill)))
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelected ? Color.primary.opacity(0.85) : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .padding(isSelected ? -3 : 0)
            }
            .contentShape(Circle())
    }
}
