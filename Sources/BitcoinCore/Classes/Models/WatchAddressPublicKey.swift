import Foundation
import GRDB

public class WatchAddressPublicKey: PublicKey {
    public init(data: Data, scriptType: ScriptType) throws {
        let path = "WatchAddressPublicKey"

        switch scriptType {
            case .p2pkh, .p2wpkh:
                super.init(path: path, hashP2pkh: data)
            case .p2sh, .p2wsh, .p2wpkhSh:
                super.init(path: path, hashP2wpkhWrappedInP2sh: data)
            case .p2tr:
                super.init(path: path, convertedForP2tr: data)
            default:
                throw PublicKey.InitError.invalid
        }
    }

    required init(row: Row) throws {
        try super.init(row: row)
    }
}
