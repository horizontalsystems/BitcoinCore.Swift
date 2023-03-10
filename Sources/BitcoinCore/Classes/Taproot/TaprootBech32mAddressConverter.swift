import Foundation

public class TaprootBech32mAddressConverter: IAddressConverter {
    private let prefix: String
    private let scriptConverter: IScriptConverter
    
    public init(prefix: String, scriptConverter: IScriptConverter) {
        self.prefix = prefix
        self.scriptConverter = scriptConverter
    }
    
    public func convert(address: String) throws -> Address {
        if let taprootData = try? SegWitBech32.decode(hrp: prefix, addr: address) {
            return TaprootAddress(keyHash: taprootData.program, bech32m: address, version: taprootData.version)
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
        let bech32 = try SegWitBech32.encode(hrp: prefix, version: versionByte, program: keyHash, encoding: .bech32m)
        return TaprootAddress(keyHash: keyHash, bech32m: bech32, version: versionByte)
    }
    
    public func convert(publicKey: PublicKey, type: ScriptType) throws -> Address {
        try convert(keyHash: OpCode.scriptWPKH(publicKey.keyHash), type: type)
    }
    
}
