import SwiftUI

// MARK: - Aurora backdrop

/// Slow brand-tinted aurora behind onboarding.
///
/// Three blurred orbs on one long repeating animation — cheap enough to leave
/// running, unlike per-frame work. The palette shifts per page so moving
/// forward feels like moving somewhere.
struct OnboardingAurora: View {
    @Environment(\.peakBrand) private var brand
    var page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var drift = false

    private var tint: Color {
        switch page {
        case 0: return brand.mid
        case 1: return PeakTradeStyle.buy
        case 2: return brand.soft
        default: return brand.mid
        }
    }

    // Light mode needs materially more: a 60pt-blurred orb at low alpha over a
    // near-white canvas is invisible, which is how this read as 'flat' before.
    private var orbOpacity: Double { colorScheme == .dark ? 0.55 : 0.48 }

    var body: some View {
        ZStack {
            PeakCanvas.background

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                orb(tint, size: w * 0.9)
                    .position(x: drift ? w * 0.22 : w * 0.34, y: drift ? h * 0.20 : h * 0.28)

                orb(brand.deep, size: w * 0.75)
                    .position(x: drift ? w * 0.86 : w * 0.72, y: drift ? h * 0.34 : h * 0.24)

                orb(tint.opacity(0.7), size: w * 0.8)
                    .position(x: drift ? w * 0.62 : w * 0.5, y: drift ? h * 0.74 : h * 0.82)
            }
            .blur(radius: 48)
            .opacity(orbOpacity)
            // Colour change is animated by the caller; only the drift loops here.
            .animation(.easeInOut(duration: 1.1), value: page)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func orb(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Live odds card

/// A market card whose odds actually move.
///
/// This is the product in miniature — far more persuasive than an abstract
/// illustration. Ticks every ~1.6s, which is slow enough that
/// `.contentTransition(.numericText())` reads as premium rather than costing
/// frames (the same modifier on live quotes had to be removed for exactly that
/// reason).
struct OnboardingLiveOddsCard: View {
    @Environment(\.peakBrand) private var brand
    let question: String
    let category: String
    var seed: Double
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var odds: Double
    @State private var previous: Double
    @State private var ticking = false

    init(question: String, category: String, seed: Double, delay: Double = 0) {
        self.question = question
        self.category = category
        self.seed = seed
        self.delay = delay
        _odds = State(initialValue: seed)
        _previous = State(initialValue: seed)
    }

    private var rising: Bool { odds >= previous }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(category.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(brand.mid)
                Spacer(minLength: 0)
                Image(systemName: rising ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(rising ? PeakTradeStyle.buy : PeakTradeStyle.sell)
                    .contentTransition(.symbolEffect(.replace))
            }

            Text(question)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(PeakFormat.cents(odds))
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("YES")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            // Probability bar — the clearest read on a yes/no market.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [brand.mid, PeakTradeStyle.buy],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * odds))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(PeakCanvas.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(question), \(PeakFormat.cents(odds)) yes")
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(delay))
            ticking = true
            while !Task.isCancelled && ticking {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { break }
                // Mean-reverting, not a free random walk. An unbiased walk
                // wandered 47¢ → 90¢ within two minutes and then sat against
                // the clamp, which reads as broken rather than live. Pulling
                // back toward the seed keeps it hovering the way a real market
                // does.
                let pullHome = (seed - odds) * 0.28
                let noise = Double.random(in: -0.025...0.025)
                let next = min(0.93, max(0.07, odds + pullHome + noise))
                withAnimation(.easeInOut(duration: 0.45)) {
                    previous = odds
                    odds = next
                }
            }
        }
        .onDisappear { ticking = false }
    }
}

// MARK: - Card stack

/// Layered market cards with depth and a gentle float.
struct OnboardingMarketStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var float = false

    var body: some View {
        ZStack {
            OnboardingLiveOddsCard(
                question: "Will the Fed cut rates this quarter?",
                category: "Finance",
                seed: 0.34,
                delay: 0.8
            )
            .scaleEffect(0.88)
            .offset(y: -74)
            .opacity(0.55)
            .blur(radius: 1.2)

            OnboardingLiveOddsCard(
                question: "Presidential election winner 2028",
                category: "Politics",
                seed: 0.62,
                delay: 0.4
            )
            .scaleEffect(0.94)
            .offset(y: -38)
            .opacity(0.8)

            OnboardingLiveOddsCard(
                question: "Bitcoin above $150k before July?",
                category: "Crypto",
                seed: 0.47
            )
            .offset(y: float ? 4 : -4)
        }
        .frame(maxWidth: 300)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                float = true
            }
        }
    }
}

// MARK: - Wallet visual

/// Self-custody, shown rather than stated: a key that stays on the device.
struct OnboardingWalletBadge: View {
    @Environment(\.peakBrand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var sweep = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(brand.mid.opacity(0.22 - Double(ring) * 0.06), lineWidth: 1)
                    .frame(width: 128 + CGFloat(ring) * 42, height: 128 + CGFloat(ring) * 42)
                    .scaleEffect(pulse ? 1.04 : 0.98)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 2.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(ring) * 0.25),
                        value: pulse
                    )
            }

            Circle()
                .fill(PeakCanvas.elevated)
                .frame(width: 118, height: 118)
                .overlay {
                    Circle().strokeBorder(PeakCanvas.hairline, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 20, y: 10)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [brand.mid, PeakTradeStyle.buy],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(sweep ? 2.5 : -2.5))
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            pulse = true
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
    }
}
