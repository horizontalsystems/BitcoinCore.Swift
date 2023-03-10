import Foundation

public class SegWitBech32AddressConverter: IAddressConverter {
    private let prefix: String
    private let scriptConverter: IScriptConverter
    private let hasAdvanced: Bool

    public init(prefix: String, scriptConverter: IScriptConverter, hasAdvanced: Bool = true) {
        self.prefix = prefix
        self.scriptConverter = scriptConverter
        self.hasAdvanced = hasAdvanced
    }

    public func convert(address: String) throws -> Address {
        if let segWitData = try? SegWitBech32.decode(hrp: prefix, addr: address, hasAdvanced: hasAdvanced) {
            switch segWitData.version {
            case 0:
                var type: AddressType = .pubKeyHash
                switch segWitData.program.count {
                    case 20: type = .pubKeyHash
                    case 32: type = .scriptHash
                    default: break
                }
                return SegWitAddress(type: type, keyHash: segWitData.program, bech32: address, version: segWitData.version)
            case 1:
                guard segWitData.program.count == 32 else {
                    break
                }
                return TaprootAddress(keyHash: segWitData.program, bech32m: address, version: segWitData.version)
            default:
                break
            }
        }
        throw BitcoinCoreErrors.AddressConversion.unknownAddressType
    }

    public func convert(keyHash: Data, type: ScriptType) throws -> Address {
        let script = try scriptConverter.decode(data: keyHash)
        guard script.chunks.count == 2,
              let versionCode = script.chunks.first?.opCode,
              let versionByte = OpCode.value(fromPush: versionCode),
              let keyHash = script.chunks.last?.data else {
            throw BitcoinCoreErrors.AddressConversion.invalidAddressLength
        }
        
        let bech32Encoding: Bech32.Encoding = versionByte > 0 ? .bech32m : .bech32
        let bech32 = try SegWitBech32.encode(hrp: prefix, version: versionByte, program: keyHash, encoding: bech32Encoding)

        switch type {
            case .p2wpkh:
                return SegWitAddress(type: AddressType.pubKeyHash, keyHash: keyHash, bech32: bech32, version: versionByte)
            case .p2wsh:
                return SegWitAddress(type: AddressType.scriptHash, keyHash: keyHash, bech32: bech32, version: versionByte)
            case .p2tr:
                return TaprootAddress(keyHash: keyHash, bech32m: bech32, version: versionByte)
            default: throw BitcoinCoreErrors.AddressConversion.unknownAddressType
        }
    }

    public func convert(publicKey: PublicKey, type: ScriptType) throws -> Address {
        switch type {
            case .p2wpkh, .p2wsh:
                return try convert(keyHash:  OpCode.segWitOutputScript(publicKey.keyHash, versionByte: 0), type: type)
            case .p2tr:
                return try convert(keyHash:  OpCode.segWitOutputScript(publicKey.raw, versionByte: 1), type: type)
            default: throw BitcoinCoreErrors.AddressConversion.unknownAddressType
        }
    }

}
