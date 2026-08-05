import SwiftUI
import UIKit

/// Post-trade completion — TRADE RECEIPT as the hero, then Share / X / Done.
struct TradeCelebrationSheet: View {
    let result: TradeCelebrationResult
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var atmosphere = false
    @State private var bloom = false
    @State private var cardIn = false
    @State private var actionsIn = false
    @State private var confetti = false
    @State private var cardImage: UIImage?
    @State private var marketIcon: UIImage?
    @State private var avatarImage: UIImage?
    @State private var blurredBackground: UIImage?

    /// Match share-card energy: buy = mint/win, sell = Peak teal (not traffic red).
    private var accent: Color {
        result.side.accentIsBuy ? PeakPostcard.winBright : PeakPostcard.tealBright
    }

    private var accentDeep: Color {
        result.side.accentIsBuy ? PeakPostcard.win : PeakPostcard.teal
    }

    var body: some View {
        ZStack {
            PeakCanvas.background.ignoresSafeArea()

            PeakAtmosphereMesh(intensity: atmosphere ? 1.0 : 0.28)
                .opacity(atmosphere ? 0.95 : 0.55)
                .animation(reduceMotion ? nil : PeakMotion.soft, value: atmosphere)
                .allowsHitTesting(false)

            accentBloom
                .allowsHitTesting(false)

            PeakConfettiBurst(accent: accent, active: confetti && !reduceMotion)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                receiptHero
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity)

                actionColumn
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 26)
            }
        }
        .onAppear { runEntrance() }
        .task {
            await renderShareCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.headline) \(result.outcomeLabel). Trade receipt.")
    }

    // MARK: - Accent bloom

    /// Soft radial wash behind the receipt — presence without clutter.
    private var accentBloom: some View {
        GeometryReader { geo in
            let midY = geo.size.height * 0.38
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(bloom ? 0.34 : 0),
                                accent.opacity(bloom ? 0.10 : 0),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 12,
                            endRadius: min(geo.size.width, geo.size.height) * 0.55
                        )
                    )
                    .frame(width: geo.size.width * 1.15, height: geo.size.height * 0.62)
                    .position(x: geo.size.width * 0.5, y: midY)
                    .blur(radius: reduceMotion ? 0 : 28)
                    .scaleEffect(bloom ? 1.0 : 0.72)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentDeep.opacity(bloom ? 0.18 : 0),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 160
                        )
                    )
                    .frame(width: geo.size.width * 0.7, height: geo.size.height * 0.36)
                    .position(x: geo.size.width * 0.5, y: midY)
                    .blur(radius: reduceMotion ? 0 : 18)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Receipt hero

    /// Live `PeakTradeShareCard` immediately; swaps to the rendered share image
    /// once ready so on-screen matches what Share / X paste.
    private var receiptHero: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width / PeakPostcard.cardWidth,
                geo.size.height / PeakPostcard.tradeCardHeight
            )
            let w = PeakPostcard.cardWidth * scale
            let h = PeakPostcard.tradeCardHeight * scale

            Group {
                if let cardImage {
                    Image(uiImage: cardImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: 28 * scale, style: .continuous))
                } else {
                    PeakTradeShareCard(
                        result: result,
                        icon: marketIcon,
                        avatar: avatarImage,
                        blurredBackground: blurredBackground
                    )
                    .scaleEffect(scale)
                    .frame(width: w, height: h)
                }
            }
            .shadow(color: accent.opacity(cardIn ? 0.28 : 0), radius: cardIn ? 36 : 8, y: 10)
            .shadow(color: Color.black.opacity(cardIn ? 0.38 : 0.12), radius: 24, y: 14)
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(cardIn ? 1 : 0)
            .offset(y: cardIn ? 0 : (reduceMotion ? 0 : 28))
            .scaleEffect(cardIn ? 1 : (reduceMotion ? 1 : 0.92))
            .rotation3DEffect(
                .degrees(cardIn || reduceMotion ? 0 : 6),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.65
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Trade receipt. \(result.outcomeLabel) · \(PeakFormat.usd(result.usd)) · \(result.displayTitle)"
        )
        .accessibilityAddTraits(.isImage)
    }

    // MARK: - Actions

    private var actionColumn: some View {
        VStack(spacing: 10) {
            if let cardImage {
                ShareLink(
                    item: Image(uiImage: cardImage),
                    message: Text(result.tweetText),
                    preview: SharePreview(
                        "\(result.headline) · Peak",
                        image: Image(uiImage: cardImage)
                    )
                ) {
                    PeakPrimaryCTA(
                        title: "Share",
                        systemImage: "square.and.arrow.up",
                        color: accentDeep
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share trade card")
            } else {
                PeakPrimaryCTA(
                    title: "Preparing…",
                    systemImage: "square.and.arrow.up",
                    color: accentDeep,
                    isLoading: true,
                    isEnabled: false
                )
                .accessibilityLabel("Preparing share card")
            }

            Button {
                PeakHaptics.press()
                if let cardImage {
                    UIPasteboard.general.image = cardImage
                }
                PeakXShare.openCompose(text: result.tweetText)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.body.weight(.semibold))
                    Text("Share to X")
                        .font(.headline)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .frame(minHeight: 50)
                .background(PeakCanvas.elevated, in: PeakLayout.ctaShape)
                .overlay {
                    PeakLayout.ctaShape.strokeBorder(
                        accent.opacity(0.22),
                        lineWidth: 1
                    )
                }
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
                    .padding(.vertical, 12)
                    .frame(minHeight: PeakLayout.minTap)
            }
            .peakPressable(haptic: false)
        }
        .opacity(actionsIn ? 1 : 0)
        .offset(y: actionsIn ? 0 : (reduceMotion ? 0 : 18))
    }

    // MARK: - Choreography

    private func runEntrance() {
        PeakHaptics.success()

        if reduceMotion {
            atmosphere = true
            bloom = true
            cardIn = true
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
        withAnimation(
            .spring(response: 0.58, dampingFraction: 0.78).delay(0.10)
        ) {
            cardIn = true
        }
        withAnimation(PeakMotion.soft.delay(0.36)) {
            actionsIn = true
        }
        // Confetti after the card settles — not competing with the entrance.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            confetti = true
        }
    }

    // MARK: - Share render

    private func renderShareCard() async {
        async let iconTask = PeakTradeShareCardRenderer.loadIcon(url: result.marketImageURL)
        async let avatarTask = PeakTradeShareCardRenderer.loadIcon(url: result.avatarURL)
        let (icon, avatar) = await (iconTask, avatarTask)
        let blurred = icon.flatMap { PeakShareImageBlur.blurred($0, radius: 34) }

        // Paint the live receipt as soon as art is ready, then snapshot for share.
        await MainActor.run {
            marketIcon = icon
            avatarImage = avatar
            blurredBackground = blurred
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

/// Tasteful Peak-branded particle burst — teal + accent flecks, not carnival noise.
struct PeakConfettiBurst: View {
    var accent: Color
    var active: Bool
    @Environment(\.peakBrand) private var brand
    @State private var startedAt: Date?

    /// Deterministic flecks — stable across redraws, no RNG in the view body.
    private var particles: [Particle] {
        (0..<22).map { i in
            let t = Double(i)
            return Particle(
                id: i,
                x: CGFloat(0.10 + ((t * 0.41).truncatingRemainder(dividingBy: 1)) * 0.80),
                delay: t * 0.018,
                drift: CGFloat(sin(t * 1.9) * 42),
                size: CGFloat(3.5 + Double(i % 4) * 1.1),
                kind: i % 4,
                spin: CGFloat((i % 2 == 0 ? 1 : -1) * (12 + i % 7))
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1 / 30 : 1, paused: !active)) { timeline in
            Canvas { context, size in
                guard active, let startedAt else { return }
                let t = timeline.date.timeIntervalSince(startedAt)
                guard t < 2.15 else { return }
                for p in particles {
                    let local = t - p.delay
                    guard local > 0, local < 1.65 else { continue }
                    let progress = local / 1.65
                    // Ease-out fall with a soft lift at the start.
                    let lift = CGFloat(sin(min(progress, 0.35) / 0.35 * .pi)) * 18
                    let y = size.height * (0.22 + CGFloat(progress) * 0.62) - lift
                    let x = size.width * p.x + p.drift * CGFloat(progress) * (1 - progress * 0.25)
                    let fade = Double(1 - progress)
                    let opacity = fade * fade * 0.85
                    let rect = CGRect(
                        x: x - p.size / 2,
                        y: y - p.size / 2,
                        width: p.size,
                        height: p.kind == 1 ? p.size * 0.38 : p.size
                    )
                    var ctx = context
                    ctx.opacity = opacity
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .degrees(Double(p.spin) * progress))
                    ctx.translateBy(x: -x, y: -y)

                    if p.kind == 3 {
                        // Soft disc — light particle, not a hard fleck.
                        let glow = CGRect(
                            x: x - p.size,
                            y: y - p.size,
                            width: p.size * 2,
                            height: p.size * 2
                        )
                        ctx.fill(Path(ellipseIn: glow), with: .color(color(for: p).opacity(0.55)))
                    } else {
                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: p.kind == 2 ? p.size / 2 : 1.2),
                            with: .color(color(for: p))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
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
        switch particle.kind {
        case 0: return brand.mid
        case 1: return accent
        case 2: return brand.soft
        default: return accent.opacity(0.9)
        }
    }

    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let drift: CGFloat
        let size: CGFloat
        let kind: Int
        let spin: CGFloat
    }
}
