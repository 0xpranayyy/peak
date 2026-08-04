import SwiftUI
import UIKit

/// Post-trade completion — celebration composition, share card, X + system share.
struct TradeCelebrationSheet: View {
    let result: TradeCelebrationResult
    var onDone: () -> Void

    @Environment(\.peakBrand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var appear = false
    @State private var checkScale: CGFloat = 0.4
    @State private var cardImage: UIImage?

    private var accent: Color {
        result.side.accentIsBuy ? PeakTradeStyle.buy : PeakTradeStyle.sell
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
                Spacer(minLength: 12)

                successHero
                    .padding(.horizontal, 28)

                Spacer(minLength: 20)

                tradeSummary
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)

                actionColumn
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            PeakHaptics.success()
            if reduceMotion {
                appear = true
                checkScale = 1
            } else {
                withAnimation(PeakMotion.appear) { appear = true }
                withAnimation(PeakMotion.soft.delay(0.08)) { checkScale = 1 }
            }
        }
        .task {
            await renderShareCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.headline) \(result.outcomeLabel)")
    }

    // MARK: - Hero

    private var successHero: some View {
        VStack(spacing: 18) {
            PeakAppLogo(size: 44, cornerRadius: 10)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 8)

            ZStack {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .frame(width: 88, height: 88)
                    .scaleEffect(appear ? 1 : 0.7)

                Circle()
                    .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 88, height: 88)
                    .scaleEffect(appear ? 1.08 : 0.85)
                    .opacity(appear ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(accent)
                    .scaleEffect(checkScale)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(result.headline)
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)

                Text(result.outcomeLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 8)

                if result.isPartial {
                    Text("Partial fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(PeakCanvas.inset, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary

    private var tradeSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(result.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if result.displayTitle != result.marketQuestion {
                Text(result.marketQuestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 0) {
                summaryMetric(label: "Amount", value: PeakFormat.usd(result.usd))
                summaryDivider
                summaryMetric(label: "Price", value: PeakFormat.cents(result.price))
                summaryDivider
                summaryMetric(label: "Shares", value: sharesLabel)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PeakCanvas.elevated, in: PeakLayout.cardShape)
        .overlay {
            PeakLayout.cardShape.strokeBorder(PeakCanvas.hairline, lineWidth: 1)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 14)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(PeakCanvas.hairline)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }

    private func summaryMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.body.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sharesLabel: String {
        let rounded = (result.shares * 100).rounded() / 100
        if rounded == rounded.rounded() && abs(rounded) < 1_000_000 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
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
                        color: brand.mid
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share trade card")
            } else {
                PeakPrimaryCTA(
                    title: "Preparing…",
                    systemImage: "square.and.arrow.up",
                    color: brand.mid,
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
        let icon = await PeakTradeShareCardRenderer.loadIcon(url: result.marketImageURL)
        let image = await MainActor.run {
            PeakTradeShareCardRenderer.image(result: result, icon: icon)
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
