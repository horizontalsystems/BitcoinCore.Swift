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
            guard let _payload = output.lockingScriptPayload else {
                continue
            }
            
            let payload: Data
            switch output.scriptType {
            case .p2pk:
                // If the scriptType is P2PK, we generate Address as if it was P2PKH
                payload = Crypto.ripeMd160Sha256(_payload)
            case .p2wpkhSh:
                // If the scriptType is P2WPKH(SH), we convert payload to P2SH and generate Address
                payload = Crypto.ripeMd160Sha256(OpCode.segWitOutputScript(_payload))
            default: payload = _payload
            }

            let scriptType = output.scriptType
            if let address = try? addressConverter.convert(lockingScriptPayload: payload, type: scriptType) {
                output.address = address.stringValue
            }
        }
    }

}
