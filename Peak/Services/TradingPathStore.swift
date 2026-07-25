import Foundation

/// Persists trading path + whether this user imported a Polymarket key for signing.
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

    /// Offer Import key/seed when signing still needs a key (including re-import after a failed Privy JWT path).
    var shouldOfferImport: Bool {
        if snapshot.needsImport { return true }
        guard !snapshot.imported else { return false }
        return snapshot.path == .existing
    }

    /// Blocking setup sheet should almost never show for imported / path-chosen users.
    var shouldShowSetupSheet: Bool {
        if snapshot.imported { return false }
        return needsPathChoice
    }

    /// Trading identity is settled (imported key or path chosen + linked).
    var isOnboardingComplete: Bool {
        if snapshot.imported { return true }
        if snapshot.path != nil, snapshot.syncReady { return true }
        return false
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
            if next.path == nil {
                next.path = .existing
                UserDefaults.standard.set(Path.existing.rawValue, forKey: pathKeyPrefix + userID)
            }
        }
        snapshot = next
        // Imported users never need the quiz sheet; treat as path settled.
        needsPathChoice = !next.imported && path == nil
    }

    func choose(_ path: Path) {
        let userID = ensureUserID()
        guard let userID else { return }
        UserDefaults.standard.set(path.rawValue, forKey: pathKeyPrefix + userID)
        var next = snapshot
        next.path = path
        snapshot = next
        needsPathChoice = false
    }

    /// Mark seed/key import complete and persist until logout / clear.
    func markImported(syncReady: Bool? = nil, message: String? = nil) {
        let userID = ensureUserID()
        guard let userID else { return }

        UserDefaults.standard.set(true, forKey: importedKeyPrefix + userID)
        UserDefaults.standard.set(Path.existing.rawValue, forKey: pathKeyPrefix + userID)

        var next = snapshot
        next.imported = true
        next.needsImport = false
        next.path = .existing
        if let syncReady {
            next.syncReady = syncReady
        }
        next.message = message ?? PeakUserCopy.connectedPolymarketAccount
        needsPathChoice = false
        snapshot = next
    }

    func clear() {
        if let userID = userKey {
            UserDefaults.standard.removeObject(forKey: pathKeyPrefix + userID)
            UserDefaults.standard.removeObject(forKey: importedKeyPrefix + userID)
        }
        snapshot = .empty
        needsPathChoice = false
    }

    func apply(server: [String: Any]) {
        var next = snapshot
        if let pathRaw = server["path"] as? String, let path = Path(rawValue: pathRaw) {
            next.path = path
            if let userID = userKey ?? PrivyAuthService.shared.userID {
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

        let serverNeedsImport: Bool = {
            if let needsImport = server["needsImport"] as? Bool { return needsImport }
            let code = (server["code"] as? String ?? server["cashErrorCode"] as? String)?.lowercased()
            if code == "import_wallet_required" { return true }
            if let message = server["message"] as? String ?? server["error"] as? String,
               PeakUserCopy.isImportWalletMessage(message)
            {
                return true
            }
            return false
        }()

        // Server needsImport wins over a stale local "imported" flag (e.g. SIWE import
        // that never got a working signer).
        if serverNeedsImport {
            next.needsImport = true
            next.imported = false
            if let userID = userKey ?? PrivyAuthService.shared.userID {
                UserDefaults.standard.set(false, forKey: importedKeyPrefix + userID)
            }
        } else if let imported = server["imported"] as? Bool, imported {
            next.imported = true
            next.needsImport = false
            next.path = next.path ?? .existing
            if let userID = userKey ?? PrivyAuthService.shared.userID {
                UserDefaults.standard.set(true, forKey: importedKeyPrefix + userID)
                UserDefaults.standard.set(Path.existing.rawValue, forKey: pathKeyPrefix + userID)
            }
            needsPathChoice = false
        } else if next.imported {
            next.needsImport = false
        }

        if let rawMessage = server["message"] as? String {
            next.message = PeakUserCopy.accountStatus(rawMessage)
        }
        // Avoid objectWillChange storms during multi-step sync/import.
        if next != snapshot {
            snapshot = next
        }
        if next.imported || next.path != nil {
            needsPathChoice = false
        }
    }

    /// Prefer bound key; fall back to live Privy user id and bind it.
    @discardableResult
    private func ensureUserID() -> String? {
        if let userKey { return userKey }
        if let id = PrivyAuthService.shared.userID {
            userKey = id
            return id
        }
        return nil
    }
}
