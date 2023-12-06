import Foundation
import HsExtensions

public enum SignatureScriptSerializer {
    static func deserialize(byteStream: ByteStream) -> [Data] {
        var data = [Data]()

        while byteStream.availableBytes > 0 {
            let dataSize = byteStream.read(VarInt.self)

            switch dataSize.underlyingValue {
            case 0x00:
                data.append(Data())
            case 0x01 ... 0x4B:
                data.append(byteStream.read(Data.self, count: Int(dataSize.underlyingValue)))
            case 0x4C:
                let dataSize2 = byteStream.read(UInt8.self).littleEndian
                data.append(byteStream.read(Data.self, count: Int(dataSize2)))
            case 0x4D:
                let dataSize2 = byteStream.read(UInt16.self).littleEndian
                data.append(byteStream.read(Data.self, count: Int(dataSize2)))
            case 0x4E:
                let dataSize2 = byteStream.read(UInt32.self).littleEndian
                data.append(byteStream.read(Data.self, count: Int(dataSize2)))
            case 0x4F:
                data.append(Data(from: Int8(-1)))
            case 0x51:
                data.append(Data([UInt8(0x51)]))
            case 0x52 ... 0x60:
                data.append(Data([UInt8(dataSize.underlyingValue - 0x50)]))
            default:
                ()
            }
        }

        return data
    }

    public static func deserialize(data: Data) -> [Data] {
        deserialize(byteStream: ByteStream(data))
    }
}
