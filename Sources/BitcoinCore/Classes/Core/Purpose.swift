import HdWalletKit

extension Purpose: CustomStringConvertible {

    public var scriptType: ScriptType {
        switch self {
        case .bip44: return .p2pkh
        case .bip49: return .p2wpkhSh
        case .bip84: return .p2wpkh
        }
    }

    public var description: String {
        switch self {
        case .bip44: return "bip44"
        case .bip49: return "bip49"
        case .bip84: return "bip84"
        }
    }

}
