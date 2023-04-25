import HdWalletKit
import HsToolKit
import HsExtensions

protocol IPublicKeyFetcher {
    func publicKeys(indices: Range<UInt32>, external: Bool) throws -> [PublicKey]
}

protocol IMultiAccountPublicKeyFetcher {
    var currentAccount: Int { get }
    func increaseAccount()
}

class InitialSyncer {
    weak var delegate: IInitialSyncerDelegate?

    private var tasks = Set<AnyTask>()

    private let storage: IStorage
    private let blockDiscovery: IBlockDiscovery
    private let publicKeyManager: IPublicKeyManager
    private let multiAccountPublicKeyFetcher: IMultiAccountPublicKeyFetcher?

    private let logger: Logger?

    init(storage: IStorage, blockDiscovery: IBlockDiscovery, publicKeyManager: IPublicKeyManager, multiAccountPublicKeyFetcher: IMultiAccountPublicKeyFetcher?, logger: Logger? = nil) {
        self.storage = storage
        self.blockDiscovery = blockDiscovery
        self.publicKeyManager = publicKeyManager
        self.multiAccountPublicKeyFetcher = multiAccountPublicKeyFetcher

        self.logger = logger
    }

    private func _sync() async {
        do {
            let array = try await blockDiscovery.discoverBlockHashes()

            let (keys, blockHashes) = array
            let sortedUniqueBlockHashes = blockHashes.unique.sorted { a, b in a.height < b.height }

            handle(keys: keys, blockHashes: sortedUniqueBlockHashes)
        } catch {
            handle(error: error)
        }
    }

    func sync() {
        Task { [weak self] in await self?._sync() }.store(in: &tasks)
    }

    private func handle(keys: [PublicKey], blockHashes: [BlockHash]) {
        var log = ""
        if let account = multiAccountPublicKeyFetcher?.currentAccount {
            log += "Account: \(account) "
        } else {
            log += "Base account "
        }
        log += "has \(keys.count) keys and \(blockHashes.count) blocks"
        logger?.debug(log)
        publicKeyManager.addKeys(keys: keys)

        // If gap shift is found
        if let multiAccountFetcher = multiAccountPublicKeyFetcher {
            if blockHashes.isEmpty {
                handleSuccess()
            } else {
                // add hashes, increase and check next account
                storage.add(blockHashes: blockHashes)
                multiAccountFetcher.increaseAccount()
                sync()
            }
        } else {
            // just add hashes and finish
            storage.add(blockHashes: blockHashes)
            handleSuccess()
        }
    }

    private func handleSuccess() {
        delegate?.onSyncSuccess()
    }

    private func handle(error: Error) {
        logger?.error(error, context: ["apiSync"], save: true)
        delegate?.onSyncFailed(error: error)
    }

}

extension InitialSyncer: IInitialSyncer {

    func terminate() {
        tasks = Set()
    }

}
