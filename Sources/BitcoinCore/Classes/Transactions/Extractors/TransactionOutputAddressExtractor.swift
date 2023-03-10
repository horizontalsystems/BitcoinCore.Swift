import Foundation
import HsCryptoKit

class TransactionOutputAddressExtractor {
    private let storage: IStorage
    private let addressConverter: IAddressConverter

    init(storage: IStorage, addressConverter: IAddressConverter) {
        self.storage = storage
        self.addressConverter = addressConverter
    }

}

extension TransactionOutputAddressExtractor: ITransactionExtractor {

    public func extract(transaction: FullTransaction) {
        for output in transaction.outputs {
            guard let key = output.keyHash else {
                continue
            }
            let keyHash: Data

            switch output.scriptType {
            case .p2pk:
                keyHash = Crypto.ripeMd160Sha256(key)
            case .p2wpkhSh:
                keyHash = Crypto.ripeMd160Sha256(OpCode.segWitOutputScript(key))
            default: keyHash = key
            }

            let scriptType = output.scriptType
            if let address = try? addressConverter.convert(keyHash: keyHash, type: scriptType) {
                output.address = address.stringValue
            }
        }
    }

}
