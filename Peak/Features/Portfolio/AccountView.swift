import SwiftUI
import UIKit

/// Sign-in: Social (Google / Apple / Email) or Import seed/key — Polymarket-style entry.
struct PeakSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var tradingPath: TradingPathStore

    var onSignedIn: (() -> Void)? = nil

    @State private var mode: Mode = .methods
    @State private var emailInput = ""
    @State private var codeInput = ""
    @State private var walletInput = ""
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var showAdvanced = false
    @State private var showImportWallet = false

    private enum Mode {
        case methods
        case email
    }

    private var title: String {
        switch mode {
        case .methods: return "Sign in"
        case .email: return "Email"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .methods:
                    methodsContent
                case .email:
                    emailContent
                }
            }
            .background(PeakMaterialBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if mode == .email {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.2)) { mode = .methods }
                            statusMessage = nil
                        }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .task { await auth.start() }
            .onChange(of: auth.isAuthenticated) { _, signedIn in
                // Don't dismiss while the import sheet is open — user still needs to paste their key.
                if signedIn, !showImportWallet {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSignedIn?()
                    dismiss()
                }
            }
            .sheet(isPresented: $showImportWallet) {
                ImportTradingWalletSheet(dismissParentOnSuccess: true) {
                    showImportWallet = false
                    onSignedIn?()
                    dismiss()
                }
                .environmentObject(auth)
                .environmentObject(tradingConfig)
                .environmentObject(wallet)
                .environmentObject(tradingPath)
            }
        }
        .presentationDetents([.medium, .large])
        .peakSheetChrome()
        .interactiveDismissDisabled(isBusy)
    }

    // MARK: - Home (social + import)

    private var methodsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    PeakAppLogo(size: 48, showGlow: true)
                        .padding(.bottom, 4)
                    Text("Sign in")
                        .font(.title2.weight(.bold))
                    Text("Continue with a social account, or import your Polymarket wallet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 28)

                VStack(spacing: 12) {
                    socialButton(
                        title: "Continue with Google",
                        systemImage: "globe"
                    ) {
                        Task { await runSocial { try await auth.loginWithGoogle() } }
                    }

                    socialButton(
                        title: "Continue with Apple",
                        systemImage: "apple.logo"
                    ) {
                        Task { await runSocial { try await auth.loginWithApple() } }
                    }

                    socialButton(
                        title: "Continue with Email",
                        systemImage: "envelope.fill"
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { mode = .email }
                    }

                    HStack {
                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                        Text("or")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                    }
                    .padding(.vertical, 8)

                    Button {
                        showImportWallet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import wallet")
                                    .font(.headline.weight(.semibold))
                                Text("Seed phrase or private key")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(
                            PeakCanvas.inset,
                            in: RoundedRectangle(cornerRadius: PeakLayout.ctaRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: PeakLayout.ctaRadius, style: .continuous)
                                .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
                        }
                    }
                    .peakPressable()
                    .disabled(isBusy)

                    Text(PeakUserCopy.securedByPrivy)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)

                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(spacing: 12) {
                        Button {
                            Task { await connectWallet() }
                        } label: {
                            Label(
                                isBusy ? "Connecting…" : "Connect wallet",
                                systemImage: "wallet.pass.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy || !WalletConnectCredentials.isConfigured)

                        #if DEBUG
                        if !WalletConnectCredentials.isConfigured {
                            Text("Add WALLETCONNECT_PROJECT_ID in PrivySecrets.local.plist to enable Connect wallet.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        #endif

                        Text("Paste a profile address to view positions only. Sign in to trade.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        TextField("0x…", text: $walletInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .padding(12)
                            .background(
                                PeakCanvas.inset,
                                in: RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                            )

                        HStack(spacing: 10) {
                            Button("Paste") {
                                if let pasted = UIPasteboard.general.string {
                                    walletInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Save") {
                                importWalletAddress()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentColor)
                            .disabled(!WalletStore.isValidAddress(walletInput))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Need help?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(statusLooksGood ? PeakTradeStyle.buy : PeakTradeStyle.sell)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                } else if case .failed(let message) = auth.phase {
                    Text(PeakUserCopy.sanitize(message, fallback: "Couldn’t sign in. Try again."))
                        .font(.footnote)
                        .foregroundStyle(PeakTradeStyle.sell)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                }

                Spacer(minLength: 24)
            }
        }
    }

    private var statusLooksGood: Bool {
        let s = statusMessage ?? ""
        return s.contains("Saved") || s.contains("Imported") || s.contains("Connected")
            || s.contains("Wallet ready") || s.contains("Deposit")
    }

    private func socialButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .frame(width: 22)
                }
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                PeakCanvas.inset,
                in: RoundedRectangle(cornerRadius: PeakLayout.ctaRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PeakLayout.ctaRadius, style: .continuous)
                    .strokeBorder(PeakCanvas.hairline, lineWidth: 1)
            }
        }
        .peakPressable()
        .disabled(isBusy)
    }

    // MARK: - Email

    private var emailContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(auth.pendingEmail == nil
                ? "Enter your email to receive a sign-in code."
                : "Enter the code sent to \(auth.pendingEmail ?? "your email").")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            VStack(spacing: 14) {
                TextField("you@email.com", text: $emailInput)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .padding(14)
                    .background(
                        PeakCanvas.inset,
                        in: RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                    )
                    .disabled(isBusy)

                if auth.pendingEmail != nil {
                    TextField("6-digit code", text: $codeInput)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(14)
                        .background(
                            PeakCanvas.inset,
                            in: RoundedRectangle(cornerRadius: PeakLayout.controlRadius, style: .continuous)
                        )
                        .disabled(isBusy)

                    Button {
                        Task { await verifyCode() }
                    } label: {
                        busyTitle("Verify")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(isBusy || codeInput.count < 4)
                }

                Button {
                    Task { await sendCode() }
                } label: {
                    busyTitle(auth.pendingEmail == nil ? "Send code" : "Resend code")
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .modifier(PeakSignInButtonStyle(prominent: auth.pendingEmail == nil))
                .disabled(isBusy || emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 24)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func busyTitle(_ title: String) -> some View {
        if isBusy {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
    }

    private func importWalletAddress() {
        let trimmed = walletInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WalletStore.isValidAddress(trimmed) else {
            statusMessage = "Enter a valid 0x address (42 characters)."
            return
        }
        wallet.save(trimmed)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        statusMessage = "Saved. Opening portfolio…"
        onSignedIn?()
        dismiss()
    }

    private func connectWallet() async {
        guard WalletConnectCredentials.isConfigured else {
            #if DEBUG
            statusMessage = "Add WALLETCONNECT_PROJECT_ID from cloud.reown.com to PrivySecrets.local.plist."
            #else
            statusMessage = "Couldn’t connect. Try again later."
            #endif
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.loginWithExternalWallet()
            await auth.finishTradingSetup(wallet: wallet, tradingConfig: tradingConfig)
            statusMessage = "Connected."
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t connect. Try again.")
        }
    }

    private func sendCode() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.sendEmailCode(to: emailInput)
            statusMessage = "Check your inbox for the code."
            codeInput = ""
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t send the code. Try again.")
        }
    }

    private func verifyCode() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.loginWithEmailCode(codeInput)
            await auth.finishTradingSetup(wallet: wallet, tradingConfig: tradingConfig)
            statusMessage = TradingPathStore.shared.snapshot.message
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t verify that code. Try again.")
        }
    }

    private func runSocial(_ work: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            await auth.finishTradingSetup(wallet: wallet, tradingConfig: tradingConfig)
            statusMessage = TradingPathStore.shared.snapshot.message
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t sign in. Try again.")
        }
    }
}

/// Import a private key or seed — signs you into Peak as that wallet (no Apple/Google gate).
struct ImportTradingWalletSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var tradingPath: TradingPathStore

    /// When opened from Sign in, close the parent sheet after a successful import.
    var dismissParentOnSuccess: Bool = false
    var onSuccess: (() -> Void)? = nil

    @State private var secretInput = ""
    @State private var failureMessage: String?
    @State private var isBusy = false
    @State private var phase: Phase = .form
    @State private var kind: ImportKind = .seed

    private enum Phase: Equatable {
        case form
        case success
        case failure
    }

    private enum ImportKind: String, CaseIterable, Identifiable {
        case seed
        case privateKey

        var id: String { rawValue }

        var title: String {
            switch self {
            case .seed: return "Seed Phrase"
            case .privateKey: return "Private Key"
            }
        }

        var placeholder: String {
            switch self {
            case .seed: return "word1 word2 word3 …"
            case .privateKey: return "0x… or hex private key"
            }
        }

        var fieldLabel: String {
            switch self {
            case .seed: return "Seed phrase"
            case .privateKey: return "Private key"
            }
        }
    }

    private var canImport: Bool {
        guard !isBusy, tradingConfig.hasBackendURL else { return false }
        return Self.isValidSecret(secretInput, kind: kind)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .form:
                    importForm
                case .success:
                    successConfirmation
                case .failure:
                    failureConfirmation
                }
            }
            .navigationTitle(phase == .form ? "Import wallet" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .success ? "Done" : "Close") {
                        if phase == .success {
                            finishSuccess()
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
            .task {
                await auth.start()
                tradingConfig.ensureBackendURLIfNeeded()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var importForm: some View {
        Form {
            Section {
                Picker("Import type", selection: $kind) {
                    ForEach(ImportKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isBusy)
                .onChange(of: kind) { _, _ in
                    secretInput = ""
                }

                SecureField(kind.placeholder, text: $secretInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .disabled(isBusy)

                Button("Paste") {
                    if let pasted = UIPasteboard.general.string {
                        secretInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .disabled(isBusy)
            } header: {
                Text(kind.fieldLabel)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        auth.isAuthenticated
                            ? "Your key is sent once securely and never stored on this device."
                            : "Paste your Polymarket \(kind == .seed ? "seed phrase" : "private key"). Peak signs you in with that wallet — no Apple or Google needed."
                    )
                    Text(PeakUserCopy.securedByPrivy)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await importSecret() }
                } label: {
                    if isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(auth.isAuthenticated ? "Import and enable trading" : "Import and sign in")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canImport)

                #if DEBUG
                if !tradingConfig.hasBackendURL {
                    Text("Trading backend isn’t configured in this build.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                #endif
            }
        }
    }

    private var successConfirmation: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(PeakTradeStyle.buy)
                .accessibilityHidden(true)
            Text(PeakUserCopy.importSuccessTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(PeakUserCopy.importSuccessBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button {
                finishSuccess()
            } label: {
                PeakPrimaryCTA(title: "Start trading", systemImage: "checkmark", color: PeakBrand.mid)
            }
            .peakPressable()
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PeakMaterialBackground())
    }

    private var failureConfirmation: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(PeakTradeStyle.sell)
                .accessibilityHidden(true)
            Text(PeakUserCopy.importFailureTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(failureMessage ?? "Something went wrong. Try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button {
                failureMessage = nil
                phase = .form
            } label: {
                PeakPrimaryCTA(title: "Try again", systemImage: "arrow.clockwise", color: PeakBrand.mid)
            }
            .peakPressable()
            .padding(.horizontal, 24)
            Button("Close") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PeakMaterialBackground())
    }

    private func finishSuccess() {
        onSuccess?()
        dismiss()
    }

    private func importSecret() async {
        let trimmed = secretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidSecret(trimmed, kind: kind) else { return }

        isBusy = true
        defer {
            isBusy = false
            secretInput = ""
        }

        do {
            try await auth.loginAndImportTradingWallet(
                trimmed,
                wallet: wallet,
                tradingConfig: tradingConfig
            )
            phase = .success
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            failureMessage = PeakUserCopy.fromError(
                error,
                fallback: "Couldn’t import that wallet. Check the key or seed and try again."
            )
            phase = .failure
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Lightweight client-side checks so Import stays disabled until input looks valid.
    private static func isValidSecret(_ raw: String, kind: ImportKind) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch kind {
        case .seed:
            let words = trimmed.split(whereSeparator: \.isWhitespace)
            return words.count >= 12
        case .privateKey:
            var hex = trimmed
            if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
                hex = String(hex.dropFirst(2))
            }
            guard hex.count == 64 else { return false }
            return hex.allSatisfy(\.isHexDigit)
        }
    }
}

/// Compact signed-in account summary.
struct AccountView: View {
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var tradingPath: TradingPathStore
    @EnvironmentObject private var peakProfile: PeakProfileStore
    @Environment(\.dismiss) private var dismiss

    var isPresentedModally: Bool = false

    @State private var statusMessage: String?
    @State private var showSignIn = false
    @State private var showImportKey = false
    @State private var showPasteAddress = false
    @State private var showTradingPath = false
    @State private var isConnectingWallet = false

    /// Path not chosen yet, or chosen but wallet still not linked / deployed.
    private var needsSetup: Bool {
        guard auth.isAuthenticated else { return false }
        if tradingPath.snapshot.imported { return false }
        if tradingPath.isOnboardingComplete { return false }
        if tradingPath.needsPathChoice { return true }
        if tradingPath.snapshot.path != nil, !tradingPath.snapshot.syncReady { return true }
        return false
    }

    var body: some View {
        Form {
            if auth.isAuthenticated {
                signedInSection
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            PeakAppLogo(size: 44, showGlow: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Peak")
                                    .font(.title3.weight(.bold))
                                Text("Account")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        Text("Sign in with a wallet or email to trade.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            showSignIn = true
                        } label: {
                            PeakPrimaryCTA(title: "Sign in", systemImage: "wallet.pass.fill", color: PeakBrand.mid)
                        }
                        .peakPressable()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    PeakAppLogo(size: 22, showGlow: false)
                    Text("Account")
                        .font(.headline)
                }
            }
            if isPresentedModally {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            PeakSignInSheet()
                .environmentObject(auth)
                .environmentObject(tradingConfig)
                .environmentObject(wallet)
                .environmentObject(tradingPath)
        }
        .sheet(isPresented: $showImportKey) {
            ImportTradingWalletSheet()
                .environmentObject(auth)
                .environmentObject(tradingConfig)
                .environmentObject(wallet)
                .environmentObject(tradingPath)
        }
        .sheet(isPresented: $showPasteAddress) {
            PasteProfileAddressSheet()
                .environmentObject(auth)
                .environmentObject(tradingConfig)
                .environmentObject(wallet)
                .environmentObject(tradingPath)
        }
        .sheet(isPresented: $showTradingPath) {
            TradingPathSheet()
                .environmentObject(auth)
                .environmentObject(tradingConfig)
                .environmentObject(wallet)
                .environmentObject(tradingPath)
        }
        .task {
            await auth.start()
            tradingPath.bind(userID: auth.userID)
            peakProfile.refresh(
                primary: auth.walletAddress ?? wallet.address,
                secondary: tradingPath.snapshot.accountWallet
            )
        }
    }

    @ViewBuilder
    private var signedInSection: some View {
        Section {
            HStack(spacing: 12) {
                PeakAvatar(
                    imageURL: peakProfile.profile?.profileImageURL,
                    title: peakProfile.displayName(
                        fallbackAddress: auth.walletAddress,
                        email: auth.email
                    ),
                    size: 48,
                    verified: peakProfile.profile?.verifiedBadge ?? false
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        peakProfile.displayName(
                            fallbackAddress: auth.walletAddress,
                            email: auth.email
                        )
                    )
                    .font(.headline)
                    .lineLimit(1)
                    if let email = auth.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let truncated = auth.truncatedWallet {
                        Text(truncated)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            if peakProfile.profile?.name != nil || peakProfile.profile?.pseudonym != nil {
                LabeledContent("Username", value: peakProfile.displayName(fallbackAddress: auth.walletAddress))
            }
            if let email = auth.email {
                LabeledContent("Account", value: email)
            }
            if let path = tradingPath.snapshot.path {
                LabeledContent("Trading", value: path == .new ? "New account" : "Existing account")
            }
            if let address = auth.walletAddress {
                LabeledContent("Address") {
                    Text(auth.truncatedWallet ?? address)
                        .font(.body.monospacedDigit())
                        .textSelection(.enabled)
                }
            }

            if needsSetup {
                Text(
                    tradingPath.needsPathChoice
                        ? "Finishing wallet setup…"
                        : "Trading setup isn’t finished yet. Tap below to continue."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if tradingPath.snapshot.imported {
                Text(PeakUserCopy.connectedPolymarketAccount)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if tradingPath.snapshot.syncReady {
                    Text(PeakUserCopy.readyToTrade)
                        .font(.caption)
                        .foregroundStyle(PeakTradeStyle.buy)
                }
            } else if let message = tradingPath.snapshot.message ?? statusMessage {
                Text(PeakUserCopy.accountStatus(message))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

            if needsSetup {
                Section {
                    Button {
                        Task {
                            await auth.finishTradingSetup(wallet: wallet, tradingConfig: tradingConfig)
                            statusMessage = tradingPath.snapshot.message
                        }
                    } label: {
                        PeakPrimaryCTA(
                            title: "Finish setup",
                            systemImage: "arrow.clockwise",
                            color: PeakBrand.mid
                        )
                    }
                    .peakPressable()
                } footer: {
                    Text("We’ll link your Polymarket account or create a Peak wallet.")
                }

                Section {
                    needHelpMenu
                }
            } else {
                Section {
                    needHelpMenu
                }
            }

        Section {
            Button("Sign out", role: .destructive) {
                Task {
                    await auth.logout()
                    statusMessage = nil
                }
            }
        }
    }

    private var needHelpMenu: some View {
        Menu {
            Button {
                Task {
                    await auth.finishTradingSetup(wallet: wallet, tradingConfig: tradingConfig)
                    statusMessage = tradingPath.snapshot.message
                }
            } label: {
                Label("Retry wallet setup", systemImage: "arrow.clockwise")
            }
            Button {
                showTradingPath = true
            } label: {
                Label("Advanced trading setup", systemImage: "arrow.triangle.branch")
            }
            Button {
                Task { await connectWalletFromAccount() }
            } label: {
                Label("Connect wallet", systemImage: "wallet.pass.fill")
            }
            .disabled(isConnectingWallet)
            if tradingPath.shouldOfferImport {
                Button {
                    showImportKey = true
                } label: {
                    Label("Import private key", systemImage: "key.fill")
                }
            }
            Button {
                showPasteAddress = true
            } label: {
                Label("Paste address", systemImage: "doc.on.clipboard")
            }
        } label: {
            Label("Need help?", systemImage: "questionmark.circle")
        }
    }

    private func connectWalletFromAccount() async {
        guard WalletConnectCredentials.isConfigured else {
            #if DEBUG
            statusMessage = "Add WALLETCONNECT_PROJECT_ID from cloud.reown.com to PrivySecrets.local.plist."
            #else
            statusMessage = "Couldn’t connect. Try again later."
            #endif
            return
        }
        isConnectingWallet = true
        defer { isConnectingWallet = false }
        do {
            try await auth.loginWithExternalWallet()
            statusMessage = try await auth.syncTradingPath(
                .existing,
                wallet: wallet,
                tradingConfig: tradingConfig,
                tradingPath: tradingPath
            )
            peakProfile.refresh(
                primary: auth.walletAddress ?? wallet.address,
                secondary: tradingPath.snapshot.accountWallet,
                force: true
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t connect. Try again.")
        }
    }
}

/// Paste a profile address to view positions (Account more-options).
private struct PasteProfileAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: PrivyAuthService
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var tradingPath: TradingPathStore

    @State private var profileAddress = ""
    @State private var statusMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0x…", text: $profileAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .disabled(isBusy)

                    Button("Paste") {
                        if let pasted = UIPasteboard.general.string {
                            profileAddress = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .disabled(isBusy)

                    Button {
                        Task { await save() }
                    } label: {
                        if isBusy {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isBusy || !WalletStore.isValidAddress(profileAddress))
                } header: {
                    Text("Profile address")
                } footer: {
                    Text("View positions only. Trading still needs Connect wallet or Import private key.")
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(PeakTradeStyle.sell)
                    }
                }
            }
            .navigationTitle("Paste address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isBusy)
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        let trimmed = profileAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WalletStore.isValidAddress(trimmed) else { return }
        isBusy = true
        defer { isBusy = false }
        tradingPath.choose(.existing)
        wallet.save(trimmed)
        do {
            _ = try await auth.syncTradingPath(
                .existing,
                wallet: wallet,
                tradingConfig: tradingConfig,
                tradingPath: tradingPath,
                accountWalletHint: trimmed
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            statusMessage = PeakUserCopy.fromError(error, fallback: "Couldn’t save that address. Try again.")
        }
    }
}

private struct PeakSignInButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
