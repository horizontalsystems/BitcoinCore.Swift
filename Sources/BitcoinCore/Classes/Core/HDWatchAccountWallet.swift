import Foundation
import HdWalletKit

extension HDWatchAccountWallet: IHDAccountWallet {

    func publicKey(index: Int, external: Bool) throws -> PublicKey {
        PublicKey(withAccount: 0, index: index, external: external, hdPublicKeyData: try publicKey(index: index, chain: external ? .external : .internal).raw)
    }

    func publicKeys(indices: Range<UInt32>, external: Bool) throws -> [PublicKey] {
        let hdPublicKeys: [HDPublicKey] = try publicKeys(indices: indices, chain: external ? .external : .internal)

        guard hdPublicKeys.count == indices.count else {
            throw HDWallet.HDWalletError.publicKeysDerivationFailed
        }

        return indices.map { index in
            let key = hdPublicKeys[Int(index - indices.lowerBound)]
            return PublicKey(withAccount: 0, index: Int(index), external: external, hdPublicKeyData: key.raw)
        }
    }

}
