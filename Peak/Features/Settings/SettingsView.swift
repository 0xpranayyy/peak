import SwiftUI

/// Central controls: account, interests, wallet, alerts, about.
struct SettingsView: View {
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var categoryPrefs: CategoryPreferencesStore
    @EnvironmentObject private var watchlist: WatchlistStore
    @EnvironmentObject private var priceAlerts: PriceAlertStore
    @EnvironmentObject private var appearance: AppearanceStore

    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                preferencesSection
                portfolioSection
                alertsSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .background(PeakMaterialBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .peakChrome()
            .task {
                await auth.start()
            }
            .confirmationDialog(
                "Show onboarding again?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Replay onboarding") {
                    categoryPrefs.hasCompletedOnboarding = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your category picks are kept unless you change them in Interests.")
            }
        }
    }

    private var accountSection: some View {
        Section {
            NavigationLink {
                AccountView()
            } label: {
                settingsRow(
                    title: "Account",
                    subtitle: accountSubtitle,
                    systemImage: auth.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle"
                )
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in to trade from Peak.")
        }
    }

    private var preferencesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                Picker("Appearance", selection: $appearance.preference) {
                    ForEach(PeakAppearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Appearance")
            }
            .padding(.vertical, 4)

            NavigationLink {
                InterestsSettingsView()
            } label: {
                settingsRow(
                    title: "Market interests",
                    subtitle: interestsSubtitle,
                    systemImage: "square.grid.2x2"
                )
            }
        } header: {
            Text("Preferences")
        } footer: {
            Text("Appearance follows your iPhone setting unless you choose Light or Dark. Pinned categories appear first on Markets.")
        }
    }

    private var portfolioSection: some View {
        Section {
            NavigationLink {
                WalletSettingsView()
            } label: {
                settingsRow(
                    title: "Read-only wallet",
                    subtitle: wallet.address.map { truncated($0) } ?? "Not set",
                    systemImage: "wallet.pass"
                )
            }
        } header: {
            Text("Portfolio")
        } footer: {
            Text("Paste a Polymarket address for view-only positions. To trade, connect a wallet or import a key under Account.")
        }
    }

    private var alertsSection: some View {
        Section {
            NavigationLink {
                PriceAlertsSettingsView()
                    .environmentObject(priceAlerts)
            } label: {
                settingsRow(
                    title: "Price alerts",
                    subtitle: alertsSubtitle,
                    systemImage: "bell"
                )
            }

            NavigationLink {
                DailyDigestSettingsView()
            } label: {
                settingsRow(
                    title: "Morning digest",
                    subtitle: "Top movers in your categories",
                    systemImage: "sun.max"
                )
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text("Price alerts use live prices while the app is open.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                PeakAppLogo(size: 48, showGlow: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Peak")
                        .font(.title3.weight(.bold))
                    Text("Version \(appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Peak, version \(appVersion)")

            legalLink(title: "Privacy Policy", key: "PEAK_PRIVACY_URL")
            legalLink(title: "Terms of Use", key: "PEAK_TERMS_URL")
            legalLink(title: "Support", key: "PEAK_SUPPORT_URL")

            Button {
                showResetConfirm = true
            } label: {
                settingsRow(
                    title: "Replay onboarding",
                    subtitle: "Brand, how Peak works, interests",
                    systemImage: "sparkles"
                )
            }
            .foregroundStyle(.primary)

            if !watchlist.eventIDs.isEmpty {
                Button(role: .destructive) {
                    watchlist.clearAll()
                } label: {
                    settingsRow(
                        title: "Clear watchlist",
                        subtitle: "\(watchlist.eventIDs.count) saved",
                        systemImage: "star.slash"
                    )
                }
            }
        } header: {
            Text("About")
        }
    }

    private var accountSubtitle: String {
        if auth.isAuthenticated {
            return auth.truncatedWallet ?? auth.email ?? "Signed in"
        }
        return "Sign in to trade"
    }

    private var interestsSubtitle: String {
        let names = categoryPrefs.interestedCategories.map(\.title)
        if names.isEmpty { return "None pinned. Showing all categories" }
        if names.count <= 3 { return names.joined(separator: ", ") }
        return "\(names.prefix(3).joined(separator: ", ")) +\(names.count - 3)"
    }

    private var alertsSubtitle: String {
        let active = priceAlerts.activeAlerts.count
        if active == 0 { return "None active" }
        return "\(active) active"
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    @ViewBuilder
    private func legalLink(title: String, key: String) -> some View {
        if let url = Self.url(forInfoKey: key) {
            Link(destination: url) {
                settingsRow(
                    title: title,
                    subtitle: nil,
                    systemImage: "arrow.up.right.square"
                )
            }
        }
    }

    private static func url(forInfoKey key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              url.scheme == "https" || url.scheme == "mailto" else { return nil }
        return url
    }

    private func truncated(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    private func settingsRow(title: String, subtitle: String?, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

struct InterestsSettingsView: View {
    @EnvironmentObject private var categoryPrefs: CategoryPreferencesStore

    var body: some View {
        List {
            Section {
                ForEach(MarketCategory.allCases) { category in
                    Button {
                        categoryPrefs.toggleInterest(category)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.systemImage)
                                .frame(width: 22)
                                .foregroundStyle(Color.accentColor)
                            Text(category.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if categoryPrefs.isInterested(category) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } header: {
                Text("Pinned on Markets")
            } footer: {
                Text("Order follows this list. Unpinned categories still appear after your picks.")
            }

            if !categoryPrefs.interestedSlugs.isEmpty {
                Section {
                    Button("Clear all pins", role: .destructive) {
                        categoryPrefs.setInterests([])
                    }
                }
            }
        }
        .navigationTitle("Interests")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WalletSettingsView: View {
    @EnvironmentObject private var wallet: WalletStore
    @State private var draft = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("0x…", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
        } header: {
            Text("Portfolio wallet")
        } footer: {
            Text("Paste the address from polymarket.com (Profile). View only. Sign in or import a key under Account to trade.")
        }

            Section {
                Button("Save") {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        wallet.clear()
                        message = "Cleared."
                    } else {
                        wallet.save(trimmed)
                        message = wallet.isValid ? "Saved." : "That doesn’t look like a valid address."
                    }
                }
                if wallet.isValid {
                    Button("Clear", role: .destructive) {
                        wallet.clear()
                        draft = ""
                        message = "Cleared."
                    }
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draft = wallet.address ?? ""
        }
    }
}
