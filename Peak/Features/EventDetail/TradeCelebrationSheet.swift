import SwiftUI
import UIKit

/// Post-trade completion — TRADE RECEIPT as the hero, then Share / X / Done.
struct TradeCelebrationSheet: View {
    let result: TradeCelebrationResult
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appear = false
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

            PeakAtmosphereMesh(intensity: appear ? 0.85 : 0.35)
                .opacity(0.9)
                .allowsHitTesting(false)

            PeakConfettiBurst(accent: accent, active: appear && !reduceMotion)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                receiptHero
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity)

                actionColumn
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            PeakHaptics.success()
            if reduceMotion {
                appear = true
            } else {
                withAnimation(PeakMotion.appear) { appear = true }
            }
        }
        .task {
            await renderShareCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.headline) \(result.outcomeLabel). Trade receipt.")
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
            .shadow(color: Color.black.opacity(0.32), radius: 28, y: 14)
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 16)
            .scaleEffect(appear ? 1 : 0.96)
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
                    PeakLayout.ctaShape.strokeBorder(PeakCanvas.hairline, lineWidth: 1)
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
                    .padding(.vertical, 14)
                    .frame(minHeight: PeakLayout.minTap)
            }
            .peakPressable(haptic: false)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 16)
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
        (0..<26).map { i in
            let t = Double(i)
            return Particle(
                id: i,
                x: CGFloat(0.08 + ((t * 0.37).truncatingRemainder(dividingBy: 1)) * 0.84),
                delay: t * 0.02,
                drift: CGFloat(sin(t * 1.7) * 36),
                size: CGFloat(4 + (i % 5)),
                kind: i % 3
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1 / 30 : 1, paused: !active)) { timeline in
            Canvas { context, size in
                guard active, let startedAt else { return }
                let t = timeline.date.timeIntervalSince(startedAt)
                guard t < 2.0 else { return }
                for p in particles {
                    let local = t - p.delay
                    guard local > 0, local < 1.55 else { continue }
                    let progress = local / 1.55
                    let y = size.height * (0.18 + CGFloat(progress) * 0.7)
                    let x = size.width * p.x + p.drift * CGFloat(progress)
                    let opacity = Double(1 - progress) * 0.9
                    let rect = CGRect(
                        x: x - p.size / 2,
                        y: y - p.size / 2,
                        width: p.size,
                        height: p.kind == 1 ? p.size * 0.45 : p.size
                    )
                    var ctx = context
                    ctx.opacity = opacity
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: p.kind == 2 ? p.size / 2 : 1.5),
                        with: .color(color(for: p))
                    )
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
        default: return brand.soft
        }
    }

    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let drift: CGFloat
        let size: CGFloat
        let kind: Int
    }
}
