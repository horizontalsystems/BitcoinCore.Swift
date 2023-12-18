import Foundation

class WatchAddressPublicKeyManager: IPublicKeyFetcher, IPublicKeyManager, IBloomFilterProvider {
    private let publicKey: WatchAddressPublicKey
    private let restoreKeyConverter: RestoreKeyConverterChain

    weak var bloomFilterManager: IBloomFilterManager?

    init(storage: IStorage, publicKey: WatchAddressPublicKey, restoreKeyConverter: RestoreKeyConverterChain) {
        self.publicKey = publicKey
        self.restoreKeyConverter = restoreKeyConverter

        if !storage.publicKeys().contains(where: { $0.path == publicKey.path }) {
            storage.add(publicKeys: [publicKey])
        }
    }

    func publicKeys(indices _: Range<UInt32>, external _: Bool) throws -> [PublicKey] {
        [publicKey]
    }

    func changePublicKey() throws -> PublicKey {
        publicKey
    }

    func receivePublicKey() throws -> PublicKey {
        publicKey
    }

    var usedPublicKeys: [PublicKey] {
        []
    }

    func fillGap() throws {
        bloomFilterManager?.regenerateBloomFilter()
    }

    func addKeys(keys _: [PublicKey]) {}

    func gapShifts() -> Bool {
        false
    }

    func publicKey(byPath _: String) throws -> PublicKey {
        throw PublicKeyManager.PublicKeyManagerError.invalidPath
    }

    func filterElements() -> [Data] {
        restoreKeyConverter.bloomFilterElements(publicKey: publicKey)
    }
}
