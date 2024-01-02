import Foundation
import HdWalletKit
import HsCryptoKit

public class MultisigKeystores {
    let cosignersCount: Int
    let minSignaturesCount: Int
    private let keystores: [HDWatchAccountWallet]

    init(cosignersCount: Int, minSignaturesCount: Int, keystores: [HDWatchAccountWallet]) {
        self.cosignersCount = cosignersCount
        self.minSignaturesCount = minSignaturesCount
        self.keystores = keystores
    }

    private func publicKeys(publicKey: PublicKey) throws -> [PublicKey] {
        try keystores.map {
            try $0.multisigPublicKey(index: publicKey.index, external: publicKey.external)
        }
    }

    func pubKeyScriptHash(publicKey: PublicKey) throws -> Data {
        let publicKeys = try publicKeys(publicKey: publicKey)
        let pubKeyScript = OpCode.push(minSignaturesCount) + publicKeys.flatMap { OpCode.push($0.raw) } + OpCode.push(cosignersCount)
        return Crypto.ripeMd160Sha256(pubKeyScript)
    }
}
