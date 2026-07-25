import Foundation
import PrivySDK

@MainActor
final class PrivyAuthService: ObservableObject {
    static let shared = PrivyAuthService()

    enum Phase: Equatable {
        case idle
        case starting
        case unauthenticated
        case authenticating
        case authenticated
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var userID: String?
    @Published private(set) var email: String?
    @Published private(set) var walletAddress: String?
    @Published private(set) var pendingEmail: String?
    @Published var showTradingPathSheet = false

    private var privy: (any Privy)?

    var isAuthenticated: Bool {
        if case .authenticated = phase { return true }
        return false
    }

    var truncatedWallet: String? {
        guard let walletAddress, walletAddress.count > 10 else { return walletAddress }
        return "\(walletAddress.prefix(6))…\(walletAddress.suffix(4))"
    }

    func start() async {
        guard PrivyCredentials.isConfigured else {
            #if DEBUG
            phase = .failed("Privy App ID / Client ID missing. Add Peak/PrivySecrets.local.plist.")
            #else
            phase = .failed("Couldn’t start sign-in. Try again later.")
            #endif
            return
        }
        guard privy == nil else {
            await refreshSession()
            return
        }

        phase = .starting
        let config = PrivyConfig(
            appId: PrivyCredentials.appID,
            appClientId: PrivyCredentials.appClientID
        )
        privy = PrivySdk.initialize(config: config)
        await refreshSession()
    }

    func refreshSession() async {
        guard let privy else {
            phase = .unauthenticated
            return
        }

        let state = await privy.getAuthState()
        switch state {
        case .authenticated(let user):
            await apply(user: user)
        case .authenticatedUnverified:
            if let user = await privy.getUser() {
                await apply(user: user)
            } else {
                clearUser()
                phase = .unauthenticated
            }
        case .unauthenticated, .notReady:
            clearUser()
            phase = .unauthenticated
        @unknown default:
            clearUser()
            phase = .unauthenticated
        }
    }

    func sendEmailCode(to rawEmail: String) async throws {
        guard let privy else { throw TradingError.notConfigured }
        let trimmed = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else {
            throw TradingError.server("Enter a valid email.")
        }
        phase = .authenticating
        do {
            try await privy.email.sendCode(to: trimmed)
            pendingEmail = trimmed
            email = trimmed
            phase = .unauthenticated
        } catch {
            phase = .failed(Self.friendlyMessage(for: error))
            throw TradingError.server(Self.friendlyMessage(for: error))
        }
    }

    func loginWithEmailCode(_ code: String) async throws {
        guard let privy else { throw TradingError.notConfigured }
        guard let pendingEmail else {
            throw TradingError.server("Request a login code first.")
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .authenticating
        do {
            let user = try await privy.email.loginWithCode(trimmed, sentTo: pendingEmail)
            await apply(user: user)
            self.pendingEmail = nil
        } catch {
            phase = .failed(Self.friendlyMessage(for: error))
            throw TradingError.server(Self.friendlyMessage(for: error))
        }
    }

    func loginWithApple() async throws {
        try await loginWithOAuth(.apple)
    }

    func loginWithGoogle() async throws {
        try await loginWithOAuth(.google)
    }

    /// Import seed/key: SIWE as that wallet (no Apple/Google), then register for trading.
    func loginAndImportTradingWallet(
        _ secret: String,
        wallet: WalletStore,
        tradingConfig: TradingConfigStore
    ) async throws {
        guard let privy else { throw TradingError.notConfigured }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TradingError.server("Enter a private key or seed phrase.")
        }

        tradingConfig.ensureBackendURLIfNeeded()
        phase = .authenticating

        do {
            if !isAuthenticated {
                let address = try await TradingProxyClient.resolveSecretAddress(secret: trimmed)
                let wc = WalletConnectAuthService.shared
                let params = SiweMessageParams(
                    appDomain: wc.siweDomain,
                    appUri: wc.siweURI,
                    chainId: wc.siweChainID,
                    walletAddress: address
                )
                let message = try await privy.siwe.generateMessage(params: params)
                let signed = try await TradingProxyClient.signSiwe(secret: trimmed, message: message)
                let metadata = WalletLoginMetadata(
                    walletClientType: .other,
                    connectorType: "imported_key"
                )
                let user = try await privy.siwe.login(
                    message: message,
                    signature: signed.signature,
                    params: params,
                    metadata: metadata
                )
                await apply(user: user)
            }

            TradingPathStore.shared.bind(userID: userID)
            TradingPathStore.shared.choose(.existing)
            showTradingPathSheet = false
            tradingConfig.ensureBackendURLIfNeeded()

            let result = try await TradingProxyClient.importWallet(secret: trimmed)
            if let address = result["address"] as? String {
                await adoptImportedWallet(address, wallet: wallet, tradingConfig: tradingConfig)
            }
            TradingPathStore.shared.apply(server: result)
            // Imported key is enough to leave onboarding — never reopen setup.
            TradingPathStore.shared.markImported(
                syncReady: true,
                message: PeakUserCopy.connectedPolymarketAccount
            )
            showTradingPathSheet = false
            phase = .authenticated
        } catch {
            let message = PeakUserCopy.fromError(
                error,
                fallback: Self.friendlyMessage(for: error)
            )
            if !isAuthenticated {
                phase = .failed(message)
            } else if case .authenticated = phase {
                // keep authenticated
            } else {
                phase = .authenticated
            }
            if let trading = error as? TradingError {
                throw trading
            }
            throw TradingError.server(message)
        }
    }

    /// WalletConnect → SIWE → Privy session with the user's existing wallet.
    func loginWithExternalWallet() async throws {
        guard let privy else { throw TradingError.notConfigured }
        phase = .authenticating
        do {
            let wc = WalletConnectAuthService.shared
            // Fresh session required for SIWE — stale Coinbase/WC sessions throw JSON-RPC 117.
            var address = try await wc.connectWallet(forceReconnect: true)

            for attempt in 1...2 {
                let params = SiweMessageParams(
                    appDomain: wc.siweDomain,
                    appUri: wc.siweURI,
                    chainId: wc.siweChainID,
                    walletAddress: address
                )
                let message = try await privy.siwe.generateMessage(params: params)
                do {
                    let signature = try await wc.personalSign(message: message, address: address)
                    let metadata = WalletLoginMetadata(
                        walletClientType: .other,
                        connectorType: "wallet_connect"
                    )
                    let user = try await privy.siwe.login(
                        message: message,
                        signature: signature,
                        params: params,
                        metadata: metadata
                    )
                    await apply(user: user)
                    TradingPathStore.shared.choose(.existing)
                    showTradingPathSheet = false
                    return
                } catch {
                    guard attempt == 1, WalletConnectAuthService.requiresReconnect(error) else {
                        throw error
                    }
                    // Regenerate SIWE after a clean reconnect (address may be unchanged).
                    address = try await wc.connectWallet(forceReconnect: true)
                }
            }
        } catch {
            let message = Self.friendlyMessage(for: error)
            if !isAuthenticated {
                phase = .failed(message)
            }
            throw TradingError.server(message)
        }
    }

    private func loginWithOAuth(_ provider: OAuthProvider) async throws {
        guard let privy else { throw TradingError.notConfigured }
        phase = .authenticating
        do {
            let user = try await privy.oAuth.login(with: provider, appUrlScheme: "peak")
            await apply(user: user)
        } catch {
            let message = Self.friendlyMessage(for: error)
            if !isAuthenticated {
                phase = .failed(message)
            }
            throw TradingError.server(message)
        }
    }

    /// Maps Privy API errors into actionable copy (DEBUG) or calm copy (Release).
    static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("invalid_native_app_id") || lower.contains("allowed app identifier") {
            #if DEBUG
            return "Add bundle ID com.pranay.peak in Privy Dashboard → App clients → Allowed app identifiers. Enable Email, Google, and Apple."
            #else
            return "Couldn’t sign in. Try again later."
            #endif
        }
        if lower.contains("invalid_origin") {
            #if DEBUG
            return "Add com.pranay.peak under Privy Dashboard → Domains."
            #else
            return "Couldn’t sign in. Try again later."
            #endif
        }
        return PeakUserCopy.sanitize(raw, fallback: "Couldn’t sign in. Try again.")
    }

    func logout() async {
        if let user = await privy?.getUser() {
            await user.logout()
        }
        TradingPathStore.shared.clear()
        PeakProfileStore.shared.clear()
        showTradingPathSheet = false
        clearUser()
        phase = .unauthenticated
    }

    /// After login: bind wallet and auto-pick existing Polymarket or new Peak wallet. No quiz sheet.
    func finishTradingSetup(wallet: WalletStore, tradingConfig: TradingConfigStore) async {
        TradingPathStore.shared.bind(userID: userID)
        if let address = walletAddress {
            wallet.save(address)
        }
        tradingConfig.ensureBackendURLIfNeeded()
        guard walletAddress != nil, tradingConfig.hasBackendURL else { return }

        // Imported keys are done — never reopen setup.
        if TradingPathStore.shared.snapshot.imported {
            showTradingPathSheet = false
            return
        }

        // Path already chosen — sync quietly; don't force the quiz on soft sync failures.
        if let path = TradingPathStore.shared.snapshot.path {
            _ = try? await syncTradingPath(
                path,
                wallet: wallet,
                tradingConfig: tradingConfig,
                tradingPath: TradingPathStore.shared
            )
            showTradingPathSheet = false
            return
        }

        // Social / first login: try existing Polymarket book, else create Peak wallet.
        await autoConfigureTradingPath(wallet: wallet, tradingConfig: tradingConfig)
    }

    /// Resolve Polymarket link or deploy a new Peak wallet without showing the quiz.
    private func autoConfigureTradingPath(wallet: WalletStore, tradingConfig: TradingConfigStore) async {
        showTradingPathSheet = false
        // Prefer existing account if Gamma finds a proxy / book for this signer.
        if (try? await syncTradingPath(
            .existing,
            wallet: wallet,
            tradingConfig: tradingConfig,
            tradingPath: TradingPathStore.shared
        )) != nil, TradingPathStore.shared.snapshot.syncReady {
            TradingPathStore.shared.choose(.existing)
            TradingPathStore.shared.apply(server: [
                "path": TradingPathStore.Path.existing.rawValue,
                "syncReady": true,
                "message": PeakUserCopy.walletReady,
            ])
            return
        }

        // No existing book — new Peak trading wallet.
        TradingPathStore.shared.choose(.new)
        _ = try? await syncTradingPath(
            .new,
            wallet: wallet,
            tradingConfig: tradingConfig,
            tradingPath: TradingPathStore.shared
        )
        TradingPathStore.shared.apply(server: [
            "path": TradingPathStore.Path.new.rawValue,
            "message": PeakUserCopy.depositToStart,
        ])
        showTradingPathSheet = false
    }

    /// Sync chosen path with backend (resolve account wallet + optional setup).
    @discardableResult
    func syncTradingPath(
        _ path: TradingPathStore.Path,
        wallet: WalletStore,
        tradingConfig: TradingConfigStore,
        tradingPath: TradingPathStore,
        accountWalletHint: String? = nil
    ) async throws -> String {
        tradingPath.choose(path)
        tradingConfig.ensureBackendURLIfNeeded()
        guard let eoa = walletAddress ?? wallet.address, tradingConfig.hasBackendURL else {
            throw TradingError.notConfigured
        }

        let session = try await TradingProxyClient.syncPrivySession(
            eoa: eoa,
            path: path.rawValue,
            accountWallet: accountWalletHint
        )
        tradingPath.apply(server: session)
        PeakProfileStore.shared.apply(
            serverProfile: session["profile"],
            address: (session["accountWallet"] as? String)
                ?? (session["signer"] as? String)
                ?? eoa
        )
        PeakProfileStore.shared.refresh(
            primary: eoa,
            secondary: session["accountWallet"] as? String,
            force: true
        )

        if let account = session["accountWallet"] as? String, WalletStore.isValidAddress(account) {
            wallet.save(account)
        } else if path == .new {
            wallet.save(eoa)
        }

        // Deploy / finalize. Must not swallow failures — new path needs syncReady before deposit/trade.
        do {
            let setup = try await TradingProxyClient.setupTrading()
            tradingPath.apply(server: setup)
            if let account = setup["accountWallet"] as? String, WalletStore.isValidAddress(account) {
                wallet.save(account)
            }
            if tradingPath.snapshot.needsImport {
                return PeakUserCopy.importWalletRequired
            }
            return (setup["message"] as? String)
                ?? (session["message"] as? String)
                ?? "Trading path saved."
        } catch let http as TradingProxyClient.HTTPBodyError {
            tradingPath.apply(server: http.body)
            if let account = http.body["accountWallet"] as? String, WalletStore.isValidAddress(account) {
                wallet.save(account)
            }
            // Existing path may already be syncReady (view-only / linked) even if CLOB setup failed.
            if path == .existing, tradingPath.snapshot.syncReady {
                let msg = (http.body["message"] as? String)
                    ?? (session["message"] as? String)
                    ?? "Account linked. Finish wallet setup if trading is still blocked."
                if tradingPath.snapshot.needsImport || PeakUserCopy.isImportWalletMessage(msg) {
                    return PeakUserCopy.importWalletRequired
                }
                return msg
            }
            throw http.tradingError
        } catch {
            // Refresh flags, then surface the failure when the wallet still isn’t ready.
            if let resolved = try? await TradingProxyClient.resolveTradingAccount(
                eoa: eoa,
                path: path.rawValue,
                accountWallet: accountWalletHint
            ) {
                tradingPath.apply(server: resolved)
            }
            if path == .existing, tradingPath.snapshot.syncReady {
                if tradingPath.snapshot.needsImport {
                    return PeakUserCopy.importWalletRequired
                }
                return (session["message"] as? String) ?? "Account linked."
            }
            throw error
        }
    }

    /// After Share-style key/seed import: prefer the imported EOA for portfolio + trading session.
    func adoptImportedWallet(_ address: String, wallet: WalletStore, tradingConfig: TradingConfigStore) async {
        guard WalletStore.isValidAddress(address) else { return }
        walletAddress = address
        wallet.save(address)
        TradingPathStore.shared.choose(.existing)
        TradingPathStore.shared.markImported(message: PeakUserCopy.connectedPolymarketAccount)
        showTradingPathSheet = false
        tradingConfig.ensureBackendURLIfNeeded()
        guard tradingConfig.hasBackendURL else { return }
        if let result = try? await TradingProxyClient.syncPrivySession(
            eoa: address,
            path: TradingPathStore.Path.existing.rawValue
        ) {
            TradingPathStore.shared.apply(server: result)
            TradingPathStore.shared.markImported(
                syncReady: (result["syncReady"] as? Bool) ?? TradingPathStore.shared.snapshot.syncReady,
                message: PeakUserCopy.connectedPolymarketAccount
            )
            PeakProfileStore.shared.apply(
                serverProfile: result["profile"],
                address: (result["accountWallet"] as? String) ?? address
            )
            PeakProfileStore.shared.refresh(
                primary: address,
                secondary: result["accountWallet"] as? String,
                force: true
            )
            if let account = result["accountWallet"] as? String, WalletStore.isValidAddress(account) {
                wallet.save(account)
            }
        }
        do {
            let setup = try await TradingProxyClient.setupTrading()
            TradingPathStore.shared.apply(server: setup)
            TradingPathStore.shared.markImported(
                syncReady: TradingPathStore.shared.snapshot.syncReady,
                message: PeakUserCopy.connectedPolymarketAccount
            )
        } catch let http as TradingProxyClient.HTTPBodyError {
            TradingPathStore.shared.apply(server: http.body)
            TradingPathStore.shared.markImported(
                syncReady: TradingPathStore.shared.snapshot.syncReady,
                message: PeakUserCopy.connectedPolymarketAccount
            )
        } catch {
            // Import already linked the EOA; setup can finish later from Account.
        }
    }

    func accessToken() async throws -> String {
        guard let user = await privy?.getUser() else {
            throw TradingError.notConfigured
        }
        return try await user.getAccessToken()
    }

    /// Apply Privy user. Never opens the trading-path quiz — social finishes via `finishTradingSetup`.
    private func apply(user: any PrivyUser) async {
        userID = user.id
        email = linkedEmail(from: user)
        TradingPathStore.shared.bind(userID: user.id)
        // Never open Set up trading from auth apply (imported or otherwise).
        showTradingPathSheet = false
        do {
            walletAddress = try await resolveWalletAddress(for: user)
            phase = .authenticated
            if let walletAddress {
                PeakProfileStore.shared.refresh(primary: walletAddress)
            }
        } catch {
            walletAddress = externalWalletAddress(from: user)
                ?? user.embeddedEthereumWallets.first?.address
            if walletAddress != nil {
                phase = .authenticated
                if let walletAddress {
                    PeakProfileStore.shared.refresh(primary: walletAddress)
                }
            } else {
                phase = .failed(PeakUserCopy.fromError(error, fallback: "Couldn’t finish sign-in. Try again."))
            }
        }
    }

    private func resolveWalletAddress(for user: any PrivyUser) async throws -> String {
        if let external = externalWalletAddress(from: user) {
            return external
        }
        return try await ensureEthereumWallet(for: user)
    }

    private func externalWalletAddress(from user: any PrivyUser) -> String? {
        for account in user.linkedAccounts {
            if case .externalWallet(let wallet) = account {
                if WalletStore.isValidAddress(wallet.address) {
                    return wallet.address
                }
            }
        }
        return nil
    }

    private func linkedEmail(from user: any PrivyUser) -> String? {
        for account in user.linkedAccounts {
            if case .email(let emailAccount) = account {
                return emailAccount.email
            }
            if case .google(let google) = account {
                return google.email
            }
            if case .apple(let apple) = account {
                return apple.email
            }
        }
        return email
    }

    private func ensureEthereumWallet(for user: any PrivyUser) async throws -> String {
        if let existing = user.embeddedEthereumWallets.first?.address {
            return existing
        }
        let wallet = try await user.createEthereumWallet(allowAdditional: false)
        return wallet.address
    }

    private func clearUser() {
        userID = nil
        email = nil
        walletAddress = nil
        pendingEmail = nil
    }
}
