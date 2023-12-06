import Foundation

public class SegWitV0Address: Address, Equatable {
    public let type: AddressType
    public let lockingScriptPayload: Data
    public let stringValue: String

    public var scriptType: ScriptType {
        switch type {
        case .pubKeyHash: return .p2wpkh
        case .scriptHash: return .p2wsh
        }
    }

    public var lockingScript: Data {
        OpCode.segWitOutputScript(lockingScriptPayload, versionByte: 0)
    }

    public init(type: AddressType, payload: Data, bech32: String) {
        self.type = type
        lockingScriptPayload = payload
        stringValue = bech32
    }

    public static func == (lhs: SegWitV0Address, rhs: some Address) -> Bool {
        guard let rhs = rhs as? SegWitV0Address else {
            return false
        }
        return lhs.type == rhs.type && lhs.lockingScriptPayload == rhs.lockingScriptPayload
    }
}
