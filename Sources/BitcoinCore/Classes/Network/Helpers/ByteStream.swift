//
//  ByteStream.swift
//  BitcoinKit
//
//  Created by Kishikawa Katsumi on 2018/02/11.
//  Copyright © 2018 Kishikawa Katsumi. All rights reserved.
//

import Foundation
import HsExtensions

public class ByteStream {
    public let data: Data
    private var offset = 0

    public var availableBytes: Int {
        data.count - offset
    }

    public var last: UInt8? {
        data[offset]
    }

    public init(_ data: Data) {
        self.data = data
    }

    public func read<T>(_ type: T.Type) -> T {
        let size = MemoryLayout<T>.size
        let value = data[offset ..< (offset + size)].hs.to(type: type)
        offset += size
        return value
    }

    public func read(_: VarInt.Type) -> VarInt {
        guard data.count > offset else {
            return VarInt(0)
        }

        let len = data[offset ..< (offset + 1)].hs.to(type: UInt8.self)
        let length: UInt64
        switch len {
        case 0 ... 252:
            length = UInt64(len)
            offset += 1
        case 0xFD:
            offset += 1
            length = UInt64(data[offset ..< (offset + 2)].hs.to(type: UInt16.self))
            offset += 2
        case 0xFE:
            offset += 1
            length = UInt64(data[offset ..< (offset + 4)].hs.to(type: UInt32.self))
            offset += 4
        case 0xFF:
            offset += 1
            length = UInt64(data[offset ..< (offset + 8)].hs.to(type: UInt64.self))
            offset += 8
        default:
            offset += 1
            length = UInt64(data[offset ..< (offset + 8)].hs.to(type: UInt64.self))
            offset += 8
        }
        return VarInt(length)
    }

    public func read(_: VarString.Type) -> VarString {
        let length = read(VarInt.self).underlyingValue
        let size = Int(length)
        let value = data[offset ..< (offset + size)].hs.to(type: String.self)
        offset += size
        return VarString(value, length: size)
    }

    public func read(_: Data.Type, count: Int) -> Data {
        let value = data[offset ..< (offset + count)]
        offset += count
        return Data(value)
    }
}
