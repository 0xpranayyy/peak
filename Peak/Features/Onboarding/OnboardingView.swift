import SwiftUI

/// First-run onboarding. Brand, product, then start.
struct OnboardingView: View {
    @EnvironmentObject private var categories: CategoryPreferencesStore
    @EnvironmentObject private var auth: PrivyAuthService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var page = 0
    @State private var appear = false
    @State private var showSignIn = false

    private let pages = OnboardingPage.allCases

    var body: some View {
        ZStack {
            OnboardingBackdrop(page: page)
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : PeakMotion.soft, value: page)

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    ForEach(pages) { step in
                        pageContent(for: step)
                            .tag(step.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
        }
        .sheet(isPresented: $showSignIn) {
            PeakSignInSheet()
                .environmentObject(auth)
                .environmentObject(TradingConfigStore.shared)
                .environmentObject(WalletStore.shared)
        }
        .onAppear {
            if reduceMotion {
                appear = true
            } else {
                withAnimation(PeakMotion.appear) { appear = true }
            }
        }
        .onChange(of: page) { old, new in
            guard old != new else { return }
            PeakHaptics.selection()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            if page > 0 {
                Button {
                    goTo(page - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            if page < pages.count - 1 {
                Button("Skip") {
                    PeakHaptics.press()
                    finish()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 44, minHeight: 44)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            OnboardingPageIndicator(count: pages.count, current: page)

            if page < pages.count - 1 {
                Button {
                    PeakHaptics.press()
                    goTo(page + 1)
                } label: {
                    PeakPrimaryCTA(title: page == 0 ? "Next" : "Continue", color: PeakBrand.mid)
                }
                .peakPressable(haptic: false)
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 10) {
                    Button {
                        PeakHaptics.success()
                        finish()
                    } label: {
                        PeakPrimaryCTA(title: "Browse markets", color: PeakBrand.mid)
                    }
                    .peakPressable(haptic: false)

                    if auth.isAuthenticated {
                        Text("Signed in")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PeakBrand.mid)
                            .padding(.vertical, 8)
                    } else {
                        Button {
                            showSignIn = true
                        } label: {
                            Text("Sign in to trade")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: PeakLayout.minTap)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(PeakBrand.mid)
                        .controlSize(.large)
                        .peakPressable()
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageContent(for step: OnboardingPage) -> some View {
        switch step {
        case .welcome:
            welcomePage
        case .markets:
            featurePage(
                title: "Live markets",
                subtitle: "Follow prices as they move. Open any event for depth, history, and a clear yes or no price.",
                visual: { OnboardingMarketsVisual() }
            )
        case .wallet:
            featurePage(
                title: "Trade with your wallet",
                subtitle: "Deposit USDC on Polygon with a QR or address. Peak does not hold your keys.",
                visual: { OnboardingWalletVisual() }
            )
        case .start:
            startPage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            PeakAppLogo(size: 120, showGlow: false)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)
                .padding(.bottom, 36)

            Text("Peak")
                .font(.largeTitle.weight(.bold))
                .tracking(-0.8)
                .foregroundStyle(.primary)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)

            Text("Prediction markets,\nbuilt for trading.")
                .font(.title3.weight(.regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 14)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 10)

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private func featurePage<Visual: View>(
        title: String,
        subtitle: String,
        @ViewBuilder visual: () -> Visual
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            visual()
                .peakAppear(delay: 0.02)
                .padding(.bottom, 40)

            Text(title)
                .font(.title.weight(.bold))
                .tracking(-0.3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .peakAppear(delay: 0.05)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.horizontal, 4)
                .peakAppear(delay: 0.08)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private var startPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            PeakAppLogo(size: 88, showGlow: false)
                .peakAppear(delay: 0.02)
                .padding(.bottom, 32)

            Text("You’re ready")
                .font(.title.weight(.bold))
                .tracking(-0.3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .peakAppear(delay: 0.05)

            Text("Browse without an account. Sign in when you want to place a trade.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 12)
                .padding(.horizontal, 8)
                .peakAppear(delay: 0.08)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Actions

    private func goTo(_ index: Int) {
        let clamped = min(max(index, 0), pages.count - 1)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : PeakMotion.soft) {
            page = clamped
        }
    }

    private func finish() {
        categories.completeOnboarding(interests: [])
    }
}

// MARK: - Page model

private enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case markets
    case wallet
    case start

    var id: Int { rawValue }
}

// MARK: - Backdrop

/// Editorial onboarding ground — flat Peak canvas (no wash / blob gradients).
private struct OnboardingBackdrop: View {
    var page: Int

    var body: some View {
        PeakCanvas.background
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - Page indicator

private struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? PeakBrand.mid : Color.secondary.opacity(0.2))
                    .frame(width: index == current ? 20 : 6, height: 6)
                    .animation(PeakMotion.snappy, value: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - Visuals

private struct OnboardingMarketsVisual: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YES")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PeakTradeStyle.buy)
                Spacer()
                Text("64¢")
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(PeakTradeStyle.buy)
                        .frame(width: geo.size.width * 0.64)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Volume $1.2M")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("NO 36¢")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isLight ? Color.white.opacity(0.92) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isLight ? 0.06 : 0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isLight ? 0.06 : 0.35), radius: 24, y: 10)
        )
        .accessibilityHidden(true)
    }
}

private struct OnboardingWalletVisual: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        VStack(spacing: 16) {
            Image(systemName: "qrcode")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(PeakBrand.mid)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isLight ? Color.white : Color.white.opacity(0.08))
                )

            Text("USDC  ·  Polygon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isLight ? Color.white.opacity(0.92) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isLight ? 0.06 : 0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isLight ? 0.06 : 0.35), radius: 24, y: 10)
        )
        .accessibilityHidden(true)
    }
}
