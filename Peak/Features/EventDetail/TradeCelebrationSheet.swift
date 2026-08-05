import SwiftUI
import UIKit

/// Post-trade completion — playful “Bought / Sold” moment, then Share / X / Done.
/// Share still exports the polished `PeakTradeShareCard` receipt.
struct TradeCelebrationSheet: View {
    let result: TradeCelebrationResult
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var atmosphere = false
    @State private var bloom = false
    @State private var contentIn = false
    @State private var heroIn = false
    @State private var actionsIn = false
    @State private var confetti = false
    @State private var cardImage: UIImage?
    @State private var marketIcon: UIImage?

    /// Buy → mint/win energy; sell → Peak teal (not muddy traffic red).
    private var accent: Color {
        result.side.accentIsBuy ? PeakPostcard.winBright : PeakPostcard.tealBright
    }

    private var accentDeep: Color {
        result.side.accentIsBuy ? PeakPostcard.win : PeakPostcard.teal
    }

    private var fillLine: String {
        let amount = PeakFormat.usd(result.usd)
        let shares = TradeCelebrationResult.formatShares(result.shares)
        let cents = PeakFormat.cents(result.price)
        return "\(amount) · \(shares) shares @ \(cents)"
    }

    var body: some View {
        ZStack {
            celebrationBackground
                .ignoresSafeArea()

            accentBloom
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                headerBlock
                    .padding(.horizontal, 28)
                    .opacity(contentIn ? 1 : 0)
                    .offset(y: contentIn ? 0 : (reduceMotion ? 0 : 16))

                Spacer(minLength: 12)

                heroWord
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120)
                    .opacity(heroIn ? 1 : 0)
                    .scaleEffect(heroIn ? 1 : (reduceMotion ? 1 : 0.86))
                    .offset(y: heroIn ? 0 : (reduceMotion ? 0 : 20))

                Spacer(minLength: 20)

                actionColumn
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .opacity(actionsIn ? 1 : 0)
                    .offset(y: actionsIn ? 0 : (reduceMotion ? 0 : 14))
            }
        }
        .onAppear { runEntrance() }
        .task { await renderShareCard() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.headline) \(result.outcomeLabel). \(result.displayTitle). \(fillLine)")
    }

    // MARK: - Background

    /// Soft Peak canvas with a light celebration wash — airy like the inspiration,
    /// teal-family, not purple or cream-terracotta.
    private var celebrationBackground: some View {
        let isLight = colorScheme == .light
        return ZStack {
            PeakCanvas.background

            // Cool pastel teal wash (light) / luminous teal depth (dark).
            LinearGradient(
                colors: isLight
                    ? [
                        Color(red: 0.90, green: 0.96, blue: 0.95),
                        Color(red: 0.94, green: 0.97, blue: 0.96),
                        Color(red: 0.96, green: 0.97, blue: 0.97),
                    ]
                    : [
                        Color(red: 0.02, green: 0.06, blue: 0.06),
                        Color.black,
                        Color(red: 0.03, green: 0.05, blue: 0.055),
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(atmosphere ? 1 : 0.55)

            PeakAtmosphereMesh(intensity: atmosphere ? (isLight ? 0.55 : 0.85) : 0.2)
                .opacity(atmosphere ? (isLight ? 0.7 : 0.9) : 0.35)
                .animation(reduceMotion ? nil : PeakMotion.soft, value: atmosphere)
                .allowsHitTesting(false)
        }
    }

    /// Soft radial wash behind the hero word.
    private var accentBloom: some View {
        GeometryReader { geo in
            let midY = geo.size.height * 0.48
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(bloom ? (colorScheme == .light ? 0.28 : 0.32) : 0),
                            accent.opacity(bloom ? 0.08 : 0),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: min(geo.size.width, geo.size.height) * 0.48
                    )
                )
                .frame(width: geo.size.width * 1.2, height: geo.size.height * 0.55)
                .position(x: geo.size.width * 0.5, y: midY)
                .blur(radius: reduceMotion ? 0 : 36)
                .scaleEffect(bloom ? 1 : 0.7)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Header (icon + question + fill)

    private var headerBlock: some View {
        VStack(spacing: 14) {
            marketThumbnail
                .shadow(color: accent.opacity(0.22), radius: 18, y: 8)
                .shadow(color: Color.black.opacity(colorScheme == .light ? 0.08 : 0.35), radius: 14, y: 6)

            Text(result.displayTitle)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .tracking(-0.3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 4) {
                Text(result.outcomeLabel.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(accentDeep)

                Text(fillLine)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if result.isPartial {
                    Text("Partial fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var marketThumbnail: some View {
        Group {
            if let marketIcon {
                Image(uiImage: marketIcon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("PeakLogo")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .light ? 0.85 : 0.18), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Hero word + confetti

    private var heroWord: some View {
        ZStack {
            PeakConfettiBurst(accent: accent, active: confetti && !reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            Text(result.headline)
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(accent)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .shadow(color: accent.opacity(colorScheme == .light ? 0.25 : 0.45), radius: 24, y: 4)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.headline)
    }

    // MARK: - Actions

    private var actionColumn: some View {
        VStack(spacing: 8) {
            if let cardImage {
                ShareLink(
                    item: Image(uiImage: cardImage),
                    message: Text(result.tweetText),
                    preview: SharePreview(
                        "\(result.headline) · Peak",
                        image: Image(uiImage: cardImage)
                    )
                ) {
                    celebrationPrimaryCTA(title: "Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share trade card")
            } else {
                celebrationPrimaryCTA(title: "Preparing…", systemImage: nil, isLoading: true)
                    .opacity(0.7)
                    .accessibilityLabel("Preparing share card")
            }

            Button {
                PeakHaptics.press()
                if let cardImage {
                    UIPasteboard.general.image = cardImage
                }
                PeakXShare.openCompose(text: result.tweetText)
            } label: {
                Text("Share to X")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .frame(minHeight: PeakLayout.minTap)
            }
            .peakPressable()
            .accessibilityLabel("Share to X")
            .accessibilityHint("Opens X with a draft tweet. Trade card image is copied for pasting.")

            Button {
                PeakHaptics.selection()
                onDone()
            } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .frame(minHeight: PeakLayout.minTap)
            }
            .peakPressable(haptic: false)
        }
    }

    /// Full-width pill — “I did it!” energy, accent-matched.
    private func celebrationPrimaryCTA(
        title: String,
        systemImage: String?,
        isLoading: Bool = false
    ) -> some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(PeakContrast.readableText(on: accentDeep, in: colorScheme))
            } else if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.system(.headline, design: .rounded).weight(.bold))
        .foregroundStyle(PeakContrast.readableText(on: accentDeep, in: colorScheme))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(minHeight: 56)
        .background(accentDeep, in: Capsule(style: .continuous))
        .shadow(color: accent.opacity(0.35), radius: 16, y: 6)
        .contentShape(Capsule(style: .continuous))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Choreography

    private func runEntrance() {
        PeakHaptics.success()

        if reduceMotion {
            atmosphere = true
            bloom = true
            contentIn = true
            heroIn = true
            actionsIn = true
            confetti = false
            return
        }

        withAnimation(PeakMotion.soft) {
            atmosphere = true
        }
        withAnimation(PeakMotion.appear.delay(0.04)) {
            bloom = true
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.82).delay(0.06)) {
            contentIn = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.16)) {
            heroIn = true
        }
        withAnimation(PeakMotion.soft.delay(0.38)) {
            actionsIn = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            confetti = true
        }
    }

    // MARK: - Share render

    private func renderShareCard() async {
        async let iconTask = PeakTradeShareCardRenderer.loadIcon(url: result.marketImageURL)
        async let avatarTask = PeakTradeShareCardRenderer.loadIcon(url: result.avatarURL)
        let (icon, avatar) = await (iconTask, avatarTask)

        await MainActor.run {
            marketIcon = icon
        }

        let image = await MainActor.run {
            PeakTradeShareCardRenderer.image(result: result, icon: icon, avatar: avatar)
        }
        await MainActor.run {
            cardImage = image
        }
    }
}

// MARK: - Confetti

/// Colorful geometric burst around the hero word — pink / orange / yellow / blue
/// sparks plus the trade accent. Honors Reduce Motion via `active`.
struct PeakConfettiBurst: View {
    var accent: Color
    var active: Bool
    @State private var startedAt: Date?

    private var particles: [Particle] {
        (0..<36).map { i in
            let t = Double(i)
            let angle = (t / 36.0) * .pi * 2 + sin(t * 0.7) * 0.35
            return Particle(
                id: i,
                angle: angle,
                distance: 48 + CGFloat((i * 17) % 90),
                delay: (t * 0.012).truncatingRemainder(dividingBy: 0.28),
                size: CGFloat(4 + Double(i % 5) * 1.4),
                kind: i % 5,
                spin: CGFloat((i % 2 == 0 ? 1 : -1) * (18 + i % 11)),
                palette: i % 6
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1 / 30 : 1, paused: !active)) { timeline in
            Canvas { context, size in
                guard active, let startedAt else { return }
                let t = timeline.date.timeIntervalSince(startedAt)
                guard t < 2.4 else { return }

                let origin = CGPoint(x: size.width * 0.5, y: size.height * 0.52)

                for p in particles {
                    let local = t - p.delay
                    guard local > 0, local < 1.8 else { continue }
                    let progress = local / 1.8
                    // Ease-out radial burst with a soft settle.
                    let eased = 1 - pow(1 - progress, 2.4)
                    let drift = p.distance * CGFloat(eased)
                    let wobble = sin(progress * .pi * 2 + Double(p.id)) * 6
                    let x = origin.x + cos(p.angle) * drift + CGFloat(wobble)
                    let y = origin.y + sin(p.angle) * drift * 0.78 - CGFloat(progress) * 12
                    let fade = Double(1 - progress)
                    let opacity = fade * fade * 0.92

                    var ctx = context
                    ctx.opacity = opacity
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .degrees(Double(p.spin) * progress))
                    ctx.translateBy(x: -x, y: -y)

                    let fill = color(for: p)
                    switch p.kind {
                    case 0:
                        // Circle
                        let r = p.size
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                            with: .color(fill)
                        )
                    case 1:
                        // Soft disc / glow
                        let r = p.size * 1.6
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                            with: .color(fill.opacity(0.55))
                        )
                    case 2:
                        // Rounded square
                        let r = p.size
                        ctx.fill(
                            Path(roundedRect: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r), cornerRadius: 1.4),
                            with: .color(fill)
                        )
                    case 3:
                        // Short dash / spark
                        let w = p.size * 1.8
                        let h = p.size * 0.35
                        ctx.fill(
                            Path(roundedRect: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), cornerRadius: h / 2),
                            with: .color(fill)
                        )
                    default:
                        // Tiny star-ish diamond
                        var path = Path()
                        let s = p.size * 0.7
                        path.move(to: CGPoint(x: x, y: y - s))
                        path.addLine(to: CGPoint(x: x + s * 0.55, y: y))
                        path.addLine(to: CGPoint(x: x, y: y + s))
                        path.addLine(to: CGPoint(x: x - s * 0.55, y: y))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(fill))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: active) { _, isActive in
            if isActive { startedAt = Date() }
        }
        .onAppear {
            if active { startedAt = Date() }
        }
    }

    private func color(for particle: Particle) -> Color {
        switch particle.palette {
        case 0: return Color(red: 1.00, green: 0.42, blue: 0.62) // pink
        case 1: return Color(red: 1.00, green: 0.58, blue: 0.28) // orange
        case 2: return Color(red: 1.00, green: 0.82, blue: 0.28) // yellow
        case 3: return Color(red: 0.28, green: 0.62, blue: 1.00) // blue
        case 4: return accent
        default: return Color.white.opacity(0.92)
        }
    }

    private struct Particle: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let delay: Double
        let size: CGFloat
        let kind: Int
        let spin: CGFloat
        let palette: Int
    }
}
