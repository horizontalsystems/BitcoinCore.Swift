import Foundation
import HdWalletKit

class AccountPublicKeyManager {
    private let restoreKeyConverter: IRestoreKeyConverter
    private let storage: IStorage
    private let hdWallet: HDAccountWallet
    weak var bloomFilterManager: IBloomFilterManager?

    init(storage: IStorage, hdWallet: HDAccountWallet, restoreKeyConverter: IRestoreKeyConverter) {
        self.storage = storage
        self.hdWallet = hdWallet
        self.restoreKeyConverter = restoreKeyConverter
    }

    private func fillGap(publicKeysWithUsedStates: [PublicKeyWithUsedState], external: Bool) throws {
        let publicKeys = publicKeysWithUsedStates.filter({ $0.publicKey.external == external })
        let gapKeysCount = gapKeysCount(publicKeyResults: publicKeys)
        var keys = [PublicKey]()

        if gapKeysCount < hdWallet.gapLimit {
            let allKeys = publicKeys.sorted(by: { $0.publicKey.index < $1.publicKey.index })
            let lastIndex = allKeys.last?.publicKey.index ?? -1
            let newKeysStartIndex = lastIndex + 1
            let indices = UInt32(newKeysStartIndex)..<UInt32(newKeysStartIndex + hdWallet.gapLimit - gapKeysCount)

            keys = try hdWallet.publicKeys(indices: indices, external: external)
        }

        addKeys(keys: keys)
    }

    private func gapKeysCount(publicKeyResults publicKeysWithUsedStates: [PublicKeyWithUsedState]) -> Int {
        if let lastUsedKey = publicKeysWithUsedStates.filter({ $0.used }).sorted(by: { $0.publicKey.index < $1.publicKey.index }).last {
            return publicKeysWithUsedStates.filter({ $0.publicKey.index > lastUsedKey.publicKey.index }).count
        } else {
            return publicKeysWithUsedStates.count
        }
    }

    private func publicKey(external: Bool) throws -> PublicKey {
        guard let unusedKey = storage.publicKeysWithUsedState()
                .filter({ $0.publicKey.external == external && !$0.used })
                .sorted(by: { $0.publicKey.index < $1.publicKey.index })
                .first else {
            throw PublicKeyManager.PublicKeyManagerError.noUnusedPublicKey
        }

        return unusedKey.publicKey
    }
}

extension AccountPublicKeyManager: IPublicKeyManager {

    func changePublicKey() throws -> PublicKey {
        try publicKey(external: false)
    }

    func receivePublicKey() throws -> PublicKey {
        try publicKey(external: true)
    }

    func fillGap() throws {
        let publicKeysWithUsedStates = storage.publicKeysWithUsedState()

        try fillGap(publicKeysWithUsedStates: publicKeysWithUsedStates, external: true)
        try fillGap(publicKeysWithUsedStates: publicKeysWithUsedStates, external: false)

        bloomFilterManager?.regenerateBloomFilter()
    }

    func addKeys(keys: [PublicKey]) {
        guard !keys.isEmpty else {
            return
        }

        storage.add(publicKeys: keys)
    }

    func gapShifts() -> Bool {
        let publicKeysWithUsedStates = storage.publicKeysWithUsedState()

        if gapKeysCount(publicKeyResults: publicKeysWithUsedStates.filter { $0.publicKey.external }) < hdWallet.gapLimit {
            return true
        }

        if gapKeysCount(publicKeyResults: publicKeysWithUsedStates.filter{ !$0.publicKey.external }) < hdWallet.gapLimit {
            return true
        }

        return false
    }

    public func publicKey(byPath path: String) throws -> PublicKey {
        let parts = path.split(separator: "/")

        guard parts.count == 2, let external = Int(parts[0]), let index = Int(parts[1]) else {
            throw PublicKeyManager.PublicKeyManagerError.invalidPath
        }

        if let publicKey = storage.publicKey(byPath: "0'/\(path)") {
            return publicKey
        }

        return try hdWallet.publicKey(index: index, external: external == 1)
    }
}

extension AccountPublicKeyManager: IBloomFilterProvider {

    func filterElements() -> [Data] {
        var elements = [Data]()

        for publicKey in storage.publicKeys() {
            elements.append(contentsOf: restoreKeyConverter.bloomFilterElements(publicKey: publicKey))
        }

        return elements
    }

}

extension AccountPublicKeyManager {

    public static func instance(storage: IStorage, hdWallet: HDAccountWallet, restoreKeyConverter: IRestoreKeyConverter) -> AccountPublicKeyManager {
        let addressManager = AccountPublicKeyManager(storage: storage, hdWallet: hdWallet, restoreKeyConverter: restoreKeyConverter)
        try? addressManager.fillGap()
        return addressManager
    }

}
