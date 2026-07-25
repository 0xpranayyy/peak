import Combine
import Foundation
import CoinbaseWalletSDK
import ReownAppKit
import WalletConnectSign
import WalletConnectNetworking
import WalletConnectRelay

/// Reown AppKit → MetaMask / Rainbow / etc. → address for Privy SIWE.
@MainActor
final class WalletConnectAuthService: ObservableObject {
    static let shared = WalletConnectAuthService()

    @Published private(set) var isConfigured = false
    @Published private(set) var connectedAddress: String?

    private var didConfigure = false
    nonisolated(unsafe) private var bag = Set<AnyCancellable>()

    private let appDomain = "peak.app"
    private let appURI = "https://peak.app"
    private let chainID = "137"

    func configureIfNeeded() {
        guard !didConfigure else { return }
        guard WalletConnectCredentials.isConfigured else {
            isConfigured = false
            return
        }

        let projectId: String = WalletConnectCredentials.projectID

        // AppMetadata requires a non-optional Redirect (`try?` → Optional crashes the type checker).
        let redirect: AppMetadata.Redirect
        do {
            redirect = try AppMetadata.Redirect(
                native: "peak://",
                universal: nil,
                linkMode: false
            )
        } catch {
            isConfigured = false
            return
        }

        let icons: [String] = ["https://polymarket.com/favicon.ico"]
        let metadata = AppMetadata(
            name: "Peak",
            description: "Polymarket on iOS",
            url: appURI,
            icons: icons,
            redirect: redirect
        )

        let socketFactory = PeakSocketFactory()
        Networking.configure(
            groupIdentifier: "group.com.pranay.peak",
            projectId: projectId,
            socketFactory: socketFactory
        )

        let sessionParams: SessionParams = Self.makeSessionParams()
        let crypto = PeakCryptoProvider()
        AppKit.configure(
            projectId: projectId,
            metadata: metadata,
            crypto: crypto,
            sessionParams: sessionParams,
            authRequestParams: nil,
            coinbaseEnabled: true,
            onError: { error in
                print("AppKit configure error:", error)
            }
        )

        connectedAddress = AppKit.instance.getAddress()
        didConfigure = true
        isConfigured = true
    }

    func handleDeeplink(_ url: URL) {
        guard didConfigure else { return }
        AppKit.instance.handleDeeplink(url)
    }

    /// - Parameter forceReconnect: Drop stale WC/Coinbase sessions first (needed for SIWE).
    func connectWallet(forceReconnect: Bool = false) async throws -> String {
        configureIfNeeded()
        guard isConfigured else {
            #if DEBUG
            throw TradingError.server(
                "Add WALLETCONNECT_PROJECT_ID from cloud.reown.com to PrivySecrets.local.plist."
            )
            #else
            throw TradingError.server("Couldn’t connect. Try again later.")
            #endif
        }

        if forceReconnect {
            let stale = AppKit.instance.getAddress()
            await disconnectExistingSessions()
            return try await presentConnectSheet(ignoringAddress: stale)
        }

        if let existing = AppKit.instance.getAddress(),
           WalletStore.isValidAddress(existing),
           hasLiveSession {
            connectedAddress = existing
            return existing
        }

        let stale = AppKit.instance.getAddress()
        return try await presentConnectSheet(ignoringAddress: stale)
    }

    func personalSign(message: String, address: String) async throws -> String {
        configureIfNeeded()
        guard isConfigured else {
            throw TradingError.server("Couldn’t connect. Try again later.")
        }
        guard hasLiveSession else {
            throw TradingError.server(
                "Wallet session expired. Disconnect Peak in your wallet app, then Connect wallet again."
            )
        }

        return try await requestPersonalSign(message: message, address: address)
    }

    /// True when AppKit has a WC session or an active Coinbase connection.
    var hasLiveSession: Bool {
        if !AppKit.instance.getSessions().isEmpty { return true }
        return CoinbaseWalletSDK.shared.isConnected()
    }

    var siweDomain: String { appDomain }
    var siweURI: String { appURI }
    var siweChainID: String { chainID }

    static func requiresReconnect(_ error: Error) -> Bool {
        let text = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return text.contains("code: 117")
            || text.contains("code\": 117")
            || text.contains("\"code\":117")
            || text.contains("disconnect your dapp")
    }

    // MARK: - Private

    func disconnectExistingSessions() async {
        // Always reset Coinbase — AppKit may report `.none` while CB still has Peak linked (117).
        _ = CoinbaseWalletSDK.shared.resetSession()

        for session in AppKit.instance.getSessions() {
            try? await AppKit.instance.disconnect(topic: session.topic)
        }
        // Also hit AppKit disconnect so its store clears `connectedWith`.
        try? await AppKit.instance.disconnect(topic: AppKit.instance.getSessions().first?.topic ?? "")
        try? await AppKit.instance.cleanup()
        connectedAddress = nil
    }

    private func presentConnectSheet(ignoringAddress: String?) async throws -> String {
        let ignored = ignoringAddress?.lowercased()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var settled = false
            let lock = NSLock()

            func finish(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !settled else { return }
                settled = true
                bag.removeAll()
                continuation.resume(with: result)
            }

            AppKit.instance.sessionSettlePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] (session: Session) in
                    Task { @MainActor in
                        guard let self else { return }
                        let fromSession = Self.address(from: session)
                        let fallback = AppKit.instance.getAddress()
                        if let address = fromSession ?? fallback {
                            self.acceptAddress(address, allowSameAsIgnored: true, ignored: ignored, finish: finish)
                        } else {
                            finish(.failure(TradingError.server("Connected wallet returned no address.")))
                        }
                    }
                }
                .store(in: &bag)

            AppKit.instance.sessionRejectionPublisher
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    finish(.failure(TradingError.server("Wallet connection was rejected.")))
                }
                .store(in: &bag)

            Task {
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                finish(.failure(TradingError.server("Wallet connection timed out.")))
            }

            // Coinbase handshake updates account without WC sessionSettle.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                for _ in 0..<120 {
                    if CoinbaseWalletSDK.shared.isConnected(),
                       let address = AppKit.instance.getAddress() {
                        acceptAddress(address, allowSameAsIgnored: false, ignored: ignored, finish: finish)
                    } else if let address = AppKit.instance.getAddress(),
                              !AppKit.instance.getSessions().isEmpty {
                        acceptAddress(address, allowSameAsIgnored: true, ignored: ignored, finish: finish)
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }

            AppKit.present()
        }
    }

    @MainActor
    private func acceptAddress(
        _ address: String,
        allowSameAsIgnored: Bool,
        ignored: String?,
        finish: @escaping (Result<String, Error>) -> Void
    ) {
        guard WalletStore.isValidAddress(address) else { return }
        if !allowSameAsIgnored, let ignored, address.lowercased() == ignored { return }
        connectedAddress = address
        finish(.success(address))
    }

    private func requestPersonalSign(message: String, address: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var done = false
            let lock = NSLock()

            func finish(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !done else { return }
                done = true
                bag.removeAll()
                continuation.resume(with: result)
            }

            AppKit.instance.sessionResponsePublisher
                .receive(on: DispatchQueue.main)
                .sink { (response: W3MResponse) in
                    switch response.result {
                    case .response(let value):
                        let raw = Self.normalizeSignature(value.stringRepresentation)
                        if raw.hasPrefix("0x") || raw.count >= 130 {
                            finish(.success(raw))
                        } else {
                            finish(.failure(TradingError.server("Unexpected signature response.")))
                        }
                    case .error(let error):
                        finish(.failure(TradingError.server("Sign failed: \(error)")))
                    }
                }
                .store(in: &bag)

            Task { @MainActor in
                do {
                    let request = W3MJSONRPC.personal_sign(address: address, message: message)
                    try await AppKit.instance.request(request)
                    AppKit.instance.launchCurrentWallet()
                } catch {
                    finish(.failure(error))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                finish(.failure(TradingError.server("Sign request timed out. Try Connect wallet again.")))
            }
        }
    }

    private static func makeSessionParams() -> SessionParams {
        let methods: Set<String> = ["personal_sign", "eth_sendTransaction", "eth_signTypedData"]
        let events: Set<String> = ["chainChanged", "accountsChanged"]
        let polygon = Blockchain("eip155:137")!
        let ethereum = Blockchain("eip155:1")!
        let blockchains: [Blockchain] = [polygon, ethereum]
        let eip155 = ProposalNamespace(
            chains: blockchains,
            methods: methods,
            events: events
        )
        let namespaces: [String: ProposalNamespace] = ["eip155": eip155]
        return SessionParams(namespaces: namespaces, sessionProperties: nil)
    }

    private static func normalizeSignature(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func address(from session: Session) -> String? {
        for (_, namespace) in session.namespaces {
            for account in namespace.accounts {
                let value = account.address
                if WalletStore.isValidAddress(value) {
                    return value
                }
            }
        }
        return nil
    }
}
