import Foundation
import HdWalletKit

class RestoreKeyConverterChain: IRestoreKeyConverter {
    var converters = [IRestoreKeyConverter]()

    func add(converter: IRestoreKeyConverter) {
        converters.append(converter)
    }

    func keysForApiRestore(publicKey: PublicKey) -> [String] {
        var keys = [String]()
        for converter in converters {
            keys.append(contentsOf: converter.keysForApiRestore(publicKey: publicKey))
        }

        return keys.unique
    }

    func bloomFilterElements(publicKey: PublicKey) -> [Data] {
        var keys = [Data]()
        for converter in converters {
            keys.append(contentsOf: converter.bloomFilterElements(publicKey: publicKey))
        }

        return keys.unique
    }
}

public class Bip44RestoreKeyConverter {
    let addressConverter: IAddressConverter

    public init(addressConverter: IAddressConverter) {
        self.addressConverter = addressConverter
    }
}

extension Bip44RestoreKeyConverter: IRestoreKeyConverter {
    public func keysForApiRestore(publicKey: PublicKey) -> [String] {
        let legacyAddress = try? addressConverter.convert(publicKey: publicKey, type: Purpose.bip44.scriptType).stringValue

        return [legacyAddress].compactMap { $0 }
    }

    public func bloomFilterElements(publicKey: PublicKey) -> [Data] {
        [publicKey.hashP2pkh, publicKey.raw]
    }
}

public class Bip49RestoreKeyConverter {
    let addressConverter: IAddressConverter

    public init(addressConverter: IAddressConverter) {
        self.addressConverter = addressConverter
    }
}

extension Bip49RestoreKeyConverter: IRestoreKeyConverter {
    public func keysForApiRestore(publicKey: PublicKey) -> [String] {
        let wpkhShAddress = try? addressConverter.convert(publicKey: publicKey, type: Purpose.bip49.scriptType).stringValue

        return [wpkhShAddress].compactMap { $0 }
    }

    public func bloomFilterElements(publicKey: PublicKey) -> [Data] {
        [publicKey.hashP2wpkhWrappedInP2sh]
    }
}

public class Bip84RestoreKeyConverter {
    let addressConverter: IAddressConverter

    public init(addressConverter: IAddressConverter) {
        self.addressConverter = addressConverter
    }
}

extension Bip84RestoreKeyConverter: IRestoreKeyConverter {
    public func keysForApiRestore(publicKey: PublicKey) -> [String] {
        let segwitAddress = try? addressConverter.convert(publicKey: publicKey, type: Purpose.bip84.scriptType).stringValue

        return [segwitAddress].compactMap { $0 }
    }

    public func bloomFilterElements(publicKey: PublicKey) -> [Data] {
        [publicKey.hashP2pkh]
    }
}

public class Bip86RestoreKeyConverter {
    let addressConverter: IAddressConverter

    public init(addressConverter: IAddressConverter) {
        self.addressConverter = addressConverter
    }
}

extension Bip86RestoreKeyConverter: IRestoreKeyConverter {
    public func keysForApiRestore(publicKey: PublicKey) -> [String] {
        let taprootAddress = try? addressConverter.convert(publicKey: publicKey, type: Purpose.bip86.scriptType).stringValue

        return [taprootAddress].compactMap { $0 }
    }

    public func bloomFilterElements(publicKey: PublicKey) -> [Data] {
        [publicKey.convertedForP2tr]
    }
}

public class KeyHashRestoreKeyConverter: IRestoreKeyConverter {
    let scriptType: ScriptType

    public init(scriptType: ScriptType) {
        self.scriptType = scriptType
    }

    public func keysForApiRestore(publicKey: PublicKey) -> [String] {
        switch scriptType {
        case .p2tr: return [publicKey.convertedForP2tr.hs.hex]
        default: return [publicKey.hashP2pkh.hs.hex]
        }
    }

    public func bloomFilterElements(publicKey: PublicKey) -> [Data] {
        switch scriptType {
        case .p2tr: return [publicKey.convertedForP2tr]
        default: return [publicKey.hashP2pkh]
        }
    }
}

public class BlockchairCashRestoreKeyConverter {
    let addressConverter: IAddressConverter
    private let prefixCount: Int

    public init(addressConverter: IAddressConverter, prefix: String) {
        self.addressConverter = addressConverter
        prefixCount = prefix.count + 1
    }
}

extension BlockchairCashRestoreKeyConverter: IRestoreKeyConverter {
    public func keysForApiRestore(publicKey: PublicKey) -> [String] {
        let legacyAddress = try? addressConverter.convert(publicKey: publicKey, type: .p2pkh).stringValue

        return [legacyAddress].compactMap { $0 }.map { a in
            let index = a.index(a.startIndex, offsetBy: prefixCount)
            return String(a[index...])
        }
    }

    public func bloomFilterElements(publicKey: PublicKey) -> [Data] {
        [publicKey.hashP2pkh, publicKey.raw]
    }
}
