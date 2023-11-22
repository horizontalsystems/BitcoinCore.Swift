import Foundation

class WatchAddressPublicKeyManager: IPublicKeyFetcher, IPublicKeyManager, IBloomFilterProvider {
    private let publicKey: WatchAddressPublicKey
    private let restoreKeyConverter: RestoreKeyConverterChain

    weak var bloomFilterManager: IBloomFilterManager?

    init(publicKey: WatchAddressPublicKey, restoreKeyConverter: RestoreKeyConverterChain) {
        self.publicKey = publicKey
        self.restoreKeyConverter = restoreKeyConverter
    }

    func publicKeys(indices: Range<UInt32>, external: Bool) throws -> [PublicKey] {
        [publicKey]
    }

    func changePublicKey() throws -> PublicKey {
        publicKey
    }

    func receivePublicKey() throws -> PublicKey {
        publicKey
    }

    func fillGap() throws {
        bloomFilterManager?.regenerateBloomFilter()
    }

    func addKeys(keys: [PublicKey]) {}

    func gapShifts() -> Bool {
        false
    }

    func publicKey(byPath: String) throws -> PublicKey {
        throw PublicKeyManager.PublicKeyManagerError.invalidPath
    }

    func filterElements() -> [Data] {
        restoreKeyConverter.bloomFilterElements(publicKey: publicKey)
    }
}
