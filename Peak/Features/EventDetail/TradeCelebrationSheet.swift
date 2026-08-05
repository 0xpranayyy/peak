import SwiftUI
import UIKit

/// Post-trade completion — calm Peak canvas, accent reserved for Bought/Sold + Share.
/// Share still exports the polished `PeakTradeShareCard` receipt.
struct TradeCelebrationSheet: View {
    let result: TradeCelebrationResult
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var contentIn = false
    @State private var heroIn = false
    @State private var actionsIn = false
    @State private var confetti = false
    @State private var cardImage: UIImage?
    @State private var marketIcon: UIImage?

    /// Buy → mint; sell → Peak teal. Used only for hero word, CTA, confetti accents.
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

    /// Shared page margin — header, hero, and actions stay optically aligned.
    private let pageMargin: CGFloat = 28

    var body: some View {
        ZStack {
            celebrationBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                headerBlock
                    .padding(.horizontal, pageMargin)
                    .opacity(contentIn ? 1 : 0)
                    .offset(y: contentIn ? 0 : (reduceMotion ? 0 : 12))

                Spacer(minLength: 28)

                heroWord
                    .padding(.horizontal, pageMargin)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 108)
                    .opacity(heroIn ? 1 : 0)
                    .scaleEffect(heroIn ? 1 : (reduceMotion ? 1 : 0.9))
                    .offset(y: heroIn ? 0 : (reduceMotion ? 0 : 14))

                Spacer(minLength: 32)

                actionColumn
                    .padding(.horizontal, pageMargin)
                    .padding(.bottom, 20)
                    .opacity(actionsIn ? 1 : 0)
                    .offset(y: actionsIn ? 0 : (reduceMotion ? 0 : 10))
            }
            // Keep CTAs clear of the home indicator without fighting the sheet chrome.
            .safeAreaPadding(.bottom, 8)
        }
        .onAppear { runEntrance() }
        .task { await renderShareCard() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.headline) \(result.outcomeLabel). \(result.displayTitle). \(fillLine)")
    }

    // MARK: - Background

    /// Flat Peak canvas — calm charcoal / soft paper. No green fog stage.
    private var celebrationBackground: some View {
        ZStack {
            PeakCanvas.background

            // Barely-there neutral depth (ink, not teal).
            RadialGradient(
                colors: [
                    (colorScheme == .light ? Color.black : Color.white)
                        .opacity(colorScheme == .light ? 0.028 : 0.055),
                    Color.clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 20,
                endRadius: 420
            )
            .allowsHitTesting(false)
        }
    }

    // MARK: - Header (icon + question + fill)

    private var headerBlock: some View {
        VStack(spacing: 16) {
            marketThumbnail
                .shadow(color: Color.black.opacity(colorScheme == .light ? 0.10 : 0.45), radius: 16, y: 8)
                .shadow(color: Color.black.opacity(colorScheme == .light ? 0.04 : 0.2), radius: 4, y: 2)

            VStack(spacing: 8) {
                Text(result.displayTitle)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .tracking(-0.35)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(result.outcomeLabel.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                Text(fillLine)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if result.isPartial {
                    Text("Partial fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.quaternary)
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
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Hero word + confetti

    private var heroWord: some View {
        ZStack {
            // Confetti sits behind the word and bursts outward past the glyph bounds.
            PeakConfettiBurst(accent: accent, active: confetti && !reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            Text(result.headline)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .tracking(-1.2)
                .foregroundStyle(accent)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .shadow(color: accent.opacity(colorScheme == .light ? 0.18 : 0.35), radius: 18, y: 3)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.headline)
    }

    // MARK: - Actions

    private var actionColumn: some View {
        VStack(spacing: 4) {
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
                    .foregroundStyle(.primary.opacity(0.72))
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
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .frame(minHeight: PeakLayout.minTap)
            }
            .peakPressable(haptic: false)
        }
    }

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
        .padding(.vertical, 16)
        .frame(minHeight: 54)
        .background(accentDeep, in: Capsule(style: .continuous))
        .shadow(color: accent.opacity(0.22), radius: 14, y: 5)
        .contentShape(Capsule(style: .continuous))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Choreography

    private func runEntrance() {
        PeakHaptics.success()

        if reduceMotion {
            contentIn = true
            heroIn = true
            actionsIn = true
            confetti = false
            return
        }

        withAnimation(.spring(response: 0.48, dampingFraction: 0.86).delay(0.04)) {
            contentIn = true
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.78).delay(0.14)) {
            heroIn = true
        }
        withAnimation(PeakMotion.soft.delay(0.32)) {
            actionsIn = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
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

/// Sparse geometric burst around the hero word — coral / amber / sky / white
/// plus a light accent sprinkle. Honors Reduce Motion via `active`.
struct PeakConfettiBurst: View {
    var accent: Color
    var active: Bool
    @State private var startedAt: Date?

    private var particles: [Particle] {
        (0..<20).map { i in
            let t = Double(i)
            let angle = (t / 20.0) * .pi * 2 + sin(t * 0.55) * 0.22
            // Start outside the glyph so pieces don't sit on Bought/Sold.
            return Particle(
                id: i,
                angle: angle,
                distance: 72 + CGFloat((i * 19) % 70),
                delay: (t * 0.014).truncatingRemainder(dividingBy: 0.22),
                size: CGFloat(3.5 + Double(i % 4) * 1.15),
                kind: i % 4,
                spin: CGFloat((i % 2 == 0 ? 1 : -1) * (14 + i % 9)),
                palette: i % 7
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1 / 30 : 1, paused: !active)) { timeline in
            Canvas { context, size in
                guard active, let startedAt else { return }
                let t = timeline.date.timeIntervalSince(startedAt)
                guard t < 2.0 else { return }

                let origin = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

                for p in particles {
                    let local = t - p.delay
                    guard local > 0, local < 1.55 else { continue }
                    let progress = local / 1.55
                    let eased = 1 - pow(1 - progress, 2.6)
                    let drift = p.distance * CGFloat(eased)
                    let wobble = sin(progress * .pi * 1.6 + Double(p.id)) * 4
                    let x = origin.x + cos(p.angle) * drift + CGFloat(wobble)
                    let y = origin.y + sin(p.angle) * drift * 0.72 - CGFloat(progress) * 10
                    let fade = Double(1 - progress)
                    let opacity = fade * fade * 0.88

                    var ctx = context
                    ctx.opacity = opacity
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .degrees(Double(p.spin) * progress))
                    ctx.translateBy(x: -x, y: -y)

                    let fill = color(for: p)
                    switch p.kind {
                    case 0:
                        let r = p.size
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                            with: .color(fill)
                        )
                    case 1:
                        let r = p.size
                        ctx.fill(
                            Path(roundedRect: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r), cornerRadius: 1.2),
                            with: .color(fill)
                        )
                    case 2:
                        let w = p.size * 1.7
                        let h = p.size * 0.32
                        ctx.fill(
                            Path(roundedRect: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), cornerRadius: h / 2),
                            with: .color(fill)
                        )
                    default:
                        var path = Path()
                        let s = p.size * 0.65
                        path.move(to: CGPoint(x: x, y: y - s))
                        path.addLine(to: CGPoint(x: x + s * 0.5, y: y))
                        path.addLine(to: CGPoint(x: x, y: y + s))
                        path.addLine(to: CGPoint(x: x - s * 0.5, y: y))
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
        case 0: return Color(red: 1.00, green: 0.45, blue: 0.58) // coral pink
        case 1: return Color(red: 1.00, green: 0.62, blue: 0.30) // amber
        case 2: return Color(red: 1.00, green: 0.84, blue: 0.36) // gold
        case 3: return Color(red: 0.40, green: 0.68, blue: 1.00) // sky
        case 4: return Color(red: 0.72, green: 0.55, blue: 1.00) // soft violet
        case 5: return accent.opacity(0.85) // rare trade accent
        default: return Color.white.opacity(0.95)
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
