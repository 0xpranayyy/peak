import Foundation

/// Persists whether this Privy user chose "new trader" or "existing Polymarket" path.
@MainActor
final class TradingPathStore: ObservableObject {
    static let shared = TradingPathStore()

    enum Path: String, Codable, Equatable {
        case new
        case existing
    }

    enum WalletTypeName: String, Codable, Equatable {
        case eoa = "EOA"
        case polyProxy = "POLY_PROXY"
        case gnosisSafe = "GNOSIS_SAFE"
        case depositWallet = "DEPOSIT_WALLET"
        case unknown = "UNKNOWN"

        var label: String {
            switch self {
            case .eoa: return "Personal wallet"
            case .polyProxy: return "Polymarket wallet"
            case .gnosisSafe: return "Safe wallet"
            case .depositWallet: return "Trading wallet"
            case .unknown: return "Unknown"
            }
        }
    }

    struct Snapshot: Equatable {
        var path: Path?
        var signer: String?
        var accountWallet: String?
        var walletTypeName: WalletTypeName
        var syncReady: Bool
        /// Seed/key was imported into Privy for server-side signing.
        var imported: Bool
        var needsDeploy: Bool
        var builderConfigured: Bool
        var relayerConfigured: Bool
        var needsImport: Bool
        var message: String?

        static let empty = Snapshot(
            path: nil,
            signer: nil,
            accountWallet: nil,
            walletTypeName: .unknown,
            syncReady: false,
            imported: false,
            needsDeploy: false,
            builderConfigured: false,
            relayerConfigured: false,
            needsImport: false,
            message: nil
        )
    }

    @Published private(set) var snapshot: Snapshot = .empty
    @Published var needsPathChoice = false

    private let pathKeyPrefix = "peak.trading.path."
    private let importedKeyPrefix = "peak.trading.imported."
    private var userKey: String?

    /// Offer Import key/seed only when not already imported for this signed-in user.
    var shouldOfferImport: Bool {
        guard !snapshot.imported else { return false }
        if snapshot.needsImport { return true }
        return snapshot.path == .existing
    }

    func bind(userID: String?) {
        userKey = userID
        guard let userID else {
            snapshot = .empty
            needsPathChoice = false
            return
        }
        let raw = UserDefaults.standard.string(forKey: pathKeyPrefix + userID)
        let path = raw.flatMap(Path.init(rawValue:))
        var next = Snapshot.empty
        next.path = path
        next.imported = UserDefaults.standard.bool(forKey: importedKeyPrefix + userID)
        if next.imported {
            next.needsImport = false
        }
        snapshot = next
        needsPathChoice = path == nil
    }

    func choose(_ path: Path) {
        guard let userID = userKey ?? PrivyAuthService.shared.userID else { return }
        UserDefaults.standard.set(path.rawValue, forKey: pathKeyPrefix + userID)
        snapshot.path = path
        needsPathChoice = false
    }

    /// Mark seed/key import complete and persist until logout / clear.
    func markImported(syncReady: Bool? = nil, message: String? = nil) {
        guard let userID = userKey ?? PrivyAuthService.shared.userID else { return }
        UserDefaults.standard.set(true, forKey: importedKeyPrefix + userID)
        var next = snapshot
        next.imported = true
        next.needsImport = false
        next.path = next.path ?? .existing
        if let syncReady { next.syncReady = syncReady }
        next.message = message ?? PeakUserCopy.connectedPolymarketAccount
        if let userID = userKey {
            UserDefaults.standard.set(Path.existing.rawValue, forKey: pathKeyPrefix + userID)
        }
        needsPathChoice = false
        snapshot = next
    }

    func clear() {
        if let userID = userKey {
            UserDefaults.standard.removeObject(forKey: pathKeyPrefix + userID)
            UserDefaults.standard.removeObject(forKey: importedKeyPrefix + userID)
        }
        snapshot = .empty
        needsPathChoice = userKey != nil
    }

    func apply(server: [String: Any]) {
        var next = snapshot
        if let pathRaw = server["path"] as? String, let path = Path(rawValue: pathRaw) {
            next.path = path
            if let userID = userKey {
                UserDefaults.standard.set(path.rawValue, forKey: pathKeyPrefix + userID)
            }
            needsPathChoice = false
        }
        next.signer = server["signer"] as? String ?? server["eoa"] as? String ?? next.signer
        next.accountWallet = server["accountWallet"] as? String
            ?? server["safeAddress"] as? String
            ?? next.accountWallet
        if let typeName = server["walletTypeName"] as? String {
            next.walletTypeName = WalletTypeName(rawValue: typeName) ?? .unknown
        }
        // Portfolio returns `ready`; session/setup return `syncReady`.
        if let sync = server["syncReady"] as? Bool {
            next.syncReady = sync
        } else if let ready = server["ready"] as? Bool {
            next.syncReady = ready
        }
        next.needsDeploy = (server["needsDeploy"] as? Bool) ?? next.needsDeploy
        next.builderConfigured = (server["builderConfigured"] as? Bool) ?? next.builderConfigured
        next.relayerConfigured = (server["relayerConfigured"] as? Bool) ?? next.relayerConfigured

        if let imported = server["imported"] as? Bool, imported {
            next.imported = true
            next.needsImport = false
            if let userID = userKey {
                UserDefaults.standard.set(true, forKey: importedKeyPrefix + userID)
            }
        }

        if let needsImport = server["needsImport"] as? Bool {
            // Never re-offer import after a successful local/server import for this user.
            next.needsImport = next.imported ? false : needsImport
        } else if let code = (server["code"] as? String ?? server["cashErrorCode"] as? String)?.lowercased(),
                  code == "import_wallet_required"
        {
            next.needsImport = !next.imported
        } else if let message = server["message"] as? String ?? server["error"] as? String,
                  PeakUserCopy.isImportWalletMessage(message)
        {
            next.needsImport = !next.imported
        }

        if let rawMessage = server["message"] as? String {
            next.message = PeakUserCopy.accountStatus(rawMessage)
        }
        snapshot = next
    }
}
