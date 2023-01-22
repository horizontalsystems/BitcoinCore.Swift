import Foundation
import HsExtensions

/// Variable length string can be stored using a variable length integer followed by the string itself.
public struct VarString {
    public typealias StringLiteralType = String
    let length: VarInt
    let value: String

    init(_ value: String, length: Int) {
        self.value = value
        self.length = VarInt(length)
    }

    func serialized() -> Data {
        var data = Data()
        data += length.serialized()
        data += value
        return data
    }
}

extension VarString : CustomStringConvertible {
    public var description: String {
        return "\(value)"
    }
}
