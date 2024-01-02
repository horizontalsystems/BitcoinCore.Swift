import Foundation
import HsCryptoKit

public class MultisigAddressConverter: IAddressConverter {
    private let baseConverter: IAddressConverter
    private let keystores: MultisigKeystores

    public init(baseConverter: IAddressConverter, keystores: MultisigKeystores) {
        self.baseConverter = baseConverter
        self.keystores = keystores
    }

    public func convert(address: String) throws -> Address {
        try baseConverter.convert(address: address)
    }

    public func convert(lockingScriptPayload: Data, type: ScriptType) throws -> Address {
        guard type == .p2sh || type == .p2wsh else {
            throw ConvertionError.invalidType
        }

        return try baseConverter.convert(lockingScriptPayload: lockingScriptPayload, type: type)
    }

    public func convert(publicKey: PublicKey, type: ScriptType) throws -> Address {
        guard type == .p2sh || type == .p2wsh || type == .p2wshSh else {
            throw ConvertionError.invalidType
        }

        return try convert(lockingScriptPayload: keystores.pubKeyScriptHash(publicKey: publicKey), type: type)
    }
}

extension MultisigAddressConverter {
    enum ConvertionError: Error {
        case invalidType
    }
}
