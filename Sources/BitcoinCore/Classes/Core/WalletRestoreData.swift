import Foundation
import HdWalletKit

public enum WalletRestoreData {
    case seed(Data)
    case extendedKey(HDExtendedKey)

    var data: Data {
        switch self {
        case let .seed(data): return data
        case let .extendedKey(key): return key.data
        }
    }

}
