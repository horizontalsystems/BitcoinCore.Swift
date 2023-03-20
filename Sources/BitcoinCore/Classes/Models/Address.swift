import Foundation

public enum AddressType: UInt8 { case pubKeyHash = 0, scriptHash = 8 }

public protocol Address: AnyObject {
    var scriptType: ScriptType { get }
    var lockingScriptPayload: Data { get }
    var stringValue: String { get }
    var lockingScript: Data { get }
}

public class LegacyAddress: Address, Equatable {
    public let type: AddressType
    public let lockingScriptPayload: Data
    public let stringValue: String

    public var scriptType: ScriptType {
        switch type {
            case .pubKeyHash: return .p2pkh
            case .scriptHash: return .p2sh
        }
    }
    
    public var lockingScript: Data {
        switch type {
        case .pubKeyHash: return OpCode.p2pkhStart + OpCode.push(lockingScriptPayload) + OpCode.p2pkhFinish
        case .scriptHash: return OpCode.p2shStart + OpCode.push(lockingScriptPayload) + OpCode.p2shFinish
        }
    }

    public init(type: AddressType, payload: Data, base58: String) {
        self.type = type
        self.lockingScriptPayload = payload
        self.stringValue = base58
    }

    public static func ==<T: Address>(lhs: LegacyAddress, rhs: T) -> Bool {
        guard let rhs = rhs as? LegacyAddress else {
            return false
        }
        return lhs.type == rhs.type && lhs.lockingScriptPayload == rhs.lockingScriptPayload
    }
}
