import Foundation
import CryptoSwift
import BigInt
import Web3
import WalletConnectSigner

/// Keccak + secp256k1 recovery for Reown AppKit.
struct PeakCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        // Web3 marks UInt8/UInt64/BigUInt as BytesConvertible with a *throwing*
        // `init(_: BytesRepresentable)`. Avoid those overloads entirely.
        let v = EthereumQuantity(quantity: bigUInt(bytes: [signature.v]))
        let r = EthereumQuantity(quantity: bigUInt(bytes: signature.r))
        let s = EthereumQuantity(quantity: bigUInt(bytes: signature.s))
        let publicKey = try EthereumPublicKey(
            message: Array(message),
            v: v,
            r: r,
            s: s
        )
        return Data(publicKey.rawPublicKey)
    }

    func keccak256(_ data: Data) -> Data {
        Data(SHA3(variant: .keccak256).calculate(for: Array(data)))
    }

    /// Big-endian unsigned int via BigInt's Data initializer (non-throwing).
    private func bigUInt(bytes: [UInt8]) -> BigUInt {
        BigUInt(Data(bytes))
    }
}
