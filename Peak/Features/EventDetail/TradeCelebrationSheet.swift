import SwiftUI
import UIKit

/// Post-trade completion — calm Peak canvas, TRADE RECEIPT as the hero.
/// Share exports the polished `PeakTradeShareCard` (charcoal + multi-accent).
struct TradeCelebrationSheet: View {
    let result: TradeCelebrationResult
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var contentIn = false
    @State private var cardImage: UIImage?
    @State private var marketIcon: UIImage?
    @State private var avatarImage: UIImage?
    @State private var blurredBackground: UIImage?

    /// Buy → mint; sell → warm coral. Matches share-card heroes (no teal wash).
    private var accent: Color {
        result.side.accentIsBuy ? PeakPostcard.winBright : PeakPostcard.sellBright
    }

    private var accentDeep: Color {
        result.side.accentIsBuy ? PeakPostcard.win : PeakPostcard.sell
    }

    /// Shared page margin — receipt and actions stay optically aligned.
    private let pageMargin: CGFloat = 24

    var body: some View {
        ZStack {
            celebrationBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                receiptHero
                    .padding(.horizontal, pageMargin)
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity)
                    .opacity(contentIn ? 1 : 0)
                    .offset(y: contentIn ? 0 : (reduceMotion ? 0 : 14))
                    .scaleEffect(contentIn ? 1 : (reduceMotion ? 1 : 0.97))

                actionColumn
                    .padding(.horizontal, pageMargin)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .opacity(contentIn ? 1 : 0)
                    .offset(y: contentIn ? 0 : (reduceMotion ? 0 : 10))
            }
            .safeAreaPadding(.bottom, 8)
        }
        .onAppear { runEntrance() }
        .task { await renderShareCard() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.headline) \(result.outcomeLabel). Trade receipt. \(result.displayTitle)")
    }

    // MARK: - Background

    /// Flat Peak canvas — calm charcoal / soft paper. No green fog stage.
    private var celebrationBackground: some View {
        ZStack {
            PeakCanvas.background

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
            .shadow(color: Color.black.opacity(colorScheme == .light ? 0.18 : 0.40), radius: 28, y: 14)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Trade receipt. \(result.outcomeLabel) · \(PeakFormat.usd(result.usd)) · \(result.displayTitle)"
        )
        .accessibilityAddTraits(.isImage)
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
            return
        }

        withAnimation(.spring(response: 0.48, dampingFraction: 0.86).delay(0.04)) {
            contentIn = true
        }
    }

    // MARK: - Share render

    private func renderShareCard() async {
        async let iconTask = PeakTradeShareCardRenderer.loadIcon(url: result.marketImageURL)
        async let avatarTask = PeakTradeShareCardRenderer.loadIcon(url: result.avatarURL)
        let (icon, avatar) = await (iconTask, avatarTask)
        let blurred = icon.flatMap { PeakShareImageBlur.blurred($0, radius: 34) }

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
