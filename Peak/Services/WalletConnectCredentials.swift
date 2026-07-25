import Foundation

enum WalletConnectCredentials {
    static var projectID: String {
        if let path = Bundle.main.path(forResource: "PrivySecrets.local", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let id = dict["WALLETCONNECT_PROJECT_ID"] as? String,
           !id.isEmpty,
           !id.contains("YOUR_") {
            return id
        }
        return Bundle.main.object(forInfoDictionaryKey: "WALLETCONNECT_PROJECT_ID") as? String ?? ""
    }

    static var isConfigured: Bool {
        !projectID.isEmpty
    }
}
