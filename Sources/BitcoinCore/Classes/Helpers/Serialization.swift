import Foundation
import HsExtensions

public extension Data {

    func to(type: VarInt.Type) -> VarInt {
        let value: UInt64
        let length = self[0..<1].hs.to(type: UInt8.self)
        switch length {
        case 0...252:
            value = UInt64(length)
        case 0xfd:
            value = UInt64(self[1...2].hs.to(type: UInt16.self))
        case 0xfe:
            value = UInt64(self[1...4].hs.to(type: UInt32.self))
        case 0xff:
            fallthrough
        default:
            value = self[1...8].hs.to(type: UInt64.self)
        }
        return VarInt(value)
    }
}
