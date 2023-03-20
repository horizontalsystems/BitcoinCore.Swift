import Foundation

class TransactionPublicKeySetter {
    let storage: IStorage

    init(storage: IStorage) {
        self.storage = storage
    }
}

extension TransactionPublicKeySetter: ITransactionExtractor {

    public func extract(transaction: FullTransaction) {
        for output in transaction.outputs {
            if let payload = output.lockingScriptPayload {
                var publicKey: PublicKey? = nil
                
                switch output.scriptType {
                    case .p2pk:
                        publicKey = storage.publicKey(raw: payload)
                    case .p2pkh:
                        publicKey = storage.publicKey(hashP2pkh: payload)
                    case .p2sh:
                        if let _publicKey = storage.publicKey(hashP2wpkhWrappedInP2sh: payload) {
                            publicKey = _publicKey
                            output.scriptType = .p2wpkhSh
                        }
                    case .p2wpkh:
                        publicKey = storage.publicKey(hashP2pkh: payload)
                    case .p2tr:
                        publicKey = storage.publicKey(convertedForP2tr: payload)
                    default: ()
                }
                
                if let publicKey = publicKey {
                    output.set(publicKey: publicKey)
                }
            }
        }
    }

}
