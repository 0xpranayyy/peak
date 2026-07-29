import SwiftUI

/// Central controls: account, interests, wallet, alerts, about.
struct SettingsView: View {
    @Environment(\.peakBrand) private var brand
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var categoryPrefs: CategoryPreferencesStore
    @EnvironmentObject private var watchlist: WatchlistStore
    @EnvironmentObject private var priceAlerts: PriceAlertStore
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var referrals: ReferralStore

    @State private var showResetConfirm = false
    @State private var showInviteFriends = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PeakPageHeader(title: "Settings")
                        .peakPageHeaderRow()
                }

                accountSection
                preferencesSection
                portfolioSection
                referralSection
                alertsSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(PeakCanvas.hairline)
            .listSectionSpacing(18)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .background(PeakMaterialBackground())
            .peakRootTab("Settings")
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
            .sheet(isPresented: $showInviteFriends) {
                InviteFriendsSheet()
                    .environmentObject(referrals)
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
            .listRowBackground(PeakCanvas.elevated)
        } header: {
            sectionHeader("Account")
        } footer: {
            Text("Sign in to trade from Peak.")
                .font(.footnote)
        }
    }

    private var preferencesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                settingsRow(
                    title: "Appearance",
                    subtitle: nil,
                    systemImage: "circle.lefthalf.filled"
                )
                Picker("Appearance", selection: $appearance.preference) {
                    ForEach(PeakAppearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Appearance")
            }
            .padding(.vertical, 2)
            .listRowBackground(PeakCanvas.elevated)

            VStack(alignment: .leading, spacing: 10) {
                settingsRow(
                    title: "Accent",
                    subtitle: appearance.theme.title,
                    systemImage: "paintpalette"
                )
                ThemeSwatchRow(selection: $appearance.theme)
            }
            .padding(.vertical, 2)
            .listRowBackground(PeakCanvas.elevated)

            NavigationLink {
                InterestsSettingsView()
            } label: {
                settingsRow(
                    title: "Market interests",
                    subtitle: interestsSubtitle,
                    systemImage: "square.grid.2x2"
                )
            }
            .listRowBackground(PeakCanvas.elevated)
        } header: {
            sectionHeader("Preferences")
        } footer: {
            Text("Light and Dark override your iPhone setting. Pinned categories appear first on Markets.")
                .font(.footnote)
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
            .listRowBackground(PeakCanvas.elevated)
        } header: {
            sectionHeader("Portfolio")
        } footer: {
            Text("Paste a Polymarket address for view-only positions. To trade, connect under Account.")
                .font(.footnote)
        }
    }

    private var referralSection: some View {
        Section {
            Button {
                showInviteFriends = true
            } label: {
                settingsRow(
                    title: "Invite friends",
                    subtitle: referrals.balance > 0 ? "\(referrals.balance) points" : "Share your code",
                    systemImage: "person.badge.plus"
                )
            }
            .foregroundStyle(.primary)
            .listRowBackground(PeakCanvas.elevated)
        } footer: {
            Text("Points are just for fun and don't carry any monetary or redeemable value.")
                .font(.footnote)
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
            .listRowBackground(PeakCanvas.elevated)

            NavigationLink {
                DailyDigestSettingsView()
            } label: {
                settingsRow(
                    title: "Morning digest",
                    subtitle: "Top movers in your categories",
                    systemImage: "sun.max"
                )
            }
            .listRowBackground(PeakCanvas.elevated)
        } header: {
            sectionHeader("Alerts")
        } footer: {
            Text("Price alerts use live prices while the app is open.")
                .font(.footnote)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack(spacing: 12) {
                PeakAppLogo(size: 40, showGlow: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peak")
                        .font(.body.weight(.semibold))
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .listRowBackground(PeakCanvas.elevated)
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
            .listRowBackground(PeakCanvas.elevated)

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
                .listRowBackground(PeakCanvas.elevated)
            }
        } header: {
            sectionHeader("About")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
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
            .listRowBackground(PeakCanvas.elevated)
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
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(brand.mid)
                .frame(width: 28, height: 28)
                .background(PeakCanvas.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

struct InterestsSettingsView: View {
    @Environment(\.peakBrand) private var brand
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
                                .foregroundStyle(brand.mid)
                            Text(category.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if categoryPrefs.isInterested(category) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(brand.mid)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .listRowBackground(PeakCanvas.elevated)
                }
            } header: {
                Text("Pinned on Markets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            } footer: {
                Text("Order follows this list. Unpinned categories still appear after your picks.")
            }

            if !categoryPrefs.interestedSlugs.isEmpty {
                Section {
                    Button("Clear all pins", role: .destructive) {
                        categoryPrefs.setInterests([])
                    }
                    .listRowBackground(PeakCanvas.elevated)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PeakMaterialBackground())
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
                    .listRowBackground(PeakCanvas.elevated)
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
                .listRowBackground(PeakCanvas.elevated)

                if wallet.isValid {
                    Button("Clear", role: .destructive) {
                        wallet.clear()
                        draft = ""
                        message = "Cleared."
                    }
                    .listRowBackground(PeakCanvas.elevated)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(PeakCanvas.elevated)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PeakMaterialBackground())
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draft = wallet.address ?? ""
        }
    }
}
