import Foundation

public class TaprootAddress: Address, Equatable {
    public let keyHash: Data
    public let stringValue: String
    public let version: UInt8
    public var scriptType = ScriptType.p2tr
    
    public var lockingScript: Data {
        // Data[0] - version byte, Data[1] - push keyHash
        OpCode.push(Int(version)) + OpCode.push(keyHash)
    }
    
    public init(keyHash: Data, bech32m: String, version: UInt8) {
        self.keyHash = keyHash
        self.stringValue = bech32m
        self.version = version
    }
    
    static public func ==<T: Address>(lhs: TaprootAddress, rhs: T) -> Bool {
        guard let rhs = rhs as? TaprootAddress else {
            return false
        }
        return lhs.keyHash == rhs.keyHash && lhs.version == rhs.version
    }
}
