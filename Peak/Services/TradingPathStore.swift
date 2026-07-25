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
        var needsDeploy: Bool
        var builderConfigured: Bool
        var relayerConfigured: Bool
        var message: String?

        static let empty = Snapshot(
            path: nil,
            signer: nil,
            accountWallet: nil,
            walletTypeName: .unknown,
            syncReady: false,
            needsDeploy: false,
            builderConfigured: false,
            relayerConfigured: false,
            message: nil
        )
    }

    @Published private(set) var snapshot: Snapshot = .empty
    @Published var needsPathChoice = false

    private let pathKeyPrefix = "peak.trading.path."
    private var userKey: String?

    func bind(userID: String?) {
        userKey = userID
        guard let userID else {
            snapshot = .empty
            needsPathChoice = false
            return
        }
        let raw = UserDefaults.standard.string(forKey: pathKeyPrefix + userID)
        let path = raw.flatMap(Path.init(rawValue:))
        snapshot.path = path
        needsPathChoice = path == nil
    }

    func choose(_ path: Path) {
        guard let userID = userKey ?? PrivyAuthService.shared.userID else { return }
        UserDefaults.standard.set(path.rawValue, forKey: pathKeyPrefix + userID)
        snapshot.path = path
        needsPathChoice = false
    }

    func clear() {
        if let userID = userKey {
            UserDefaults.standard.removeObject(forKey: pathKeyPrefix + userID)
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
        next.message = server["message"] as? String ?? next.message
        snapshot = next
    }
}
