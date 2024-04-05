import Combine
import Foundation
import HsExtensions
import HsToolKit
import ObjectMapper

class BlockchairApiSyncer {
    weak var listener: IApiSyncerListener?
    private var task: AnyTask?
    private var syncing: Bool = false

    private let storage: IStorage
    private let gapLimit: Int
    private let restoreKeyConverter: IRestoreKeyConverter
    private var transactionProvider: IApiTransactionProvider
    private var lastBlockProvider: BlockchairLastBlockProvider
    private let publicKeyManager: IPublicKeyManager
    private let blockchain: Blockchain
    private let apiSyncStateManager: ApiSyncStateManager

    init(storage: IStorage, gapLimit: Int, restoreKeyConverter: IRestoreKeyConverter,
         transactionProvider: IApiTransactionProvider, lastBlockProvider: BlockchairLastBlockProvider,
         publicKeyManager: IPublicKeyManager, blockchain: Blockchain,
         apiSyncStateManager: ApiSyncStateManager, logger _: Logger? = nil)
    {
        self.storage = storage
        self.gapLimit = gapLimit
        self.restoreKeyConverter = restoreKeyConverter
        self.transactionProvider = transactionProvider
        self.lastBlockProvider = lastBlockProvider
        self.publicKeyManager = publicKeyManager
        self.blockchain = blockchain
        self.apiSyncStateManager = apiSyncStateManager
    }

    private func scan() async throws {
        let allKeys = storage.publicKeys()
        try await fetchRecursive(keys: allKeys, allKeys: allKeys, stopHeight: storage.downloadedTransactionsBestBlockHeight)
        apiSyncStateManager.restored = true
        listener?.onSyncSuccess()
    }

    private func fetchRecursive(keys: [PublicKey], allKeys: [PublicKey], stopHeight: Int) async throws {
        var addressMap = [String: PublicKey]()
        var addresses = [String]()

        for key in keys {
            let restoreKeys = restoreKeyConverter.keysForApiRestore(publicKey: key)
            for address in restoreKeys {
                addresses.append(address)
                addressMap[address] = key
            }
        }

        let transactionItems = try await transactionProvider.transactions(addresses: addresses, stopHeight: stopHeight)
        var blockHashes = [BlockHash]()
        var blockHashPublicKeys = [BlockHashPublicKey]()

        for transactionItem in transactionItems {
            guard let hash = transactionItem.blockHash.hs.reversedHexData else {
                continue
            }

            var blockHash: BlockHash
            if let existing = blockHashes.first(where: { $0.headerHash == hash }) {
                blockHash = existing
            } else {
                blockHash = BlockHash(headerHash: hash, height: transactionItem.blockHeight, order: 0)
                blockHashes.append(blockHash)
            }

            for addressItem in transactionItem.apiAddressItems {
                if let address = addressItem.address, let publicKey = addressMap[address] {
                    blockHashPublicKeys.append(
                        BlockHashPublicKey(blockHash: hash, publicKeyPath: publicKey.path)
                    )
                } else if let publicKey = addressMap[addressItem.script] {
                    blockHashPublicKeys.append(
                        BlockHashPublicKey(blockHash: hash, publicKeyPath: publicKey.path)
                    )
                }
            }
        }

        storage.add(blockHashes: blockHashes)
        storage.add(blockHashPublicKeys: blockHashPublicKeys)
        listener?.transactionsFound(count: transactionItems.count)

        try publicKeyManager.fillGap()
        let _allKeys = storage.publicKeys()
        let newKeys = _allKeys.filter { !allKeys.contains($0) }

        if !newKeys.isEmpty {
            try await fetchRecursive(keys: newKeys, allKeys: _allKeys, stopHeight: stopHeight)
        }
    }

    private func syncLastBlock() async throws {
        let blockHeaderItem = try await lastBlockProvider.lastBlockHeader()
        let header = BlockHeader(
            version: 0,
            headerHash: blockHeaderItem.hash,
            previousBlockHeaderHash: Data(),
            merkleRoot: Data(),
            timestamp: blockHeaderItem.timestamp,
            bits: 0,
            nonce: 0
        )

        try blockchain.insertLastBlock(header: header, height: blockHeaderItem.height)
    }

    private func handle(error: Error) {
        listener?.onSyncFailed(error: error)
    }
}

extension BlockchairApiSyncer: IApiSyncer {
    var willSync: Bool {
        true
    }

    func sync() {
        guard !syncing else { return }

        task = Task { [weak self] in
            self?.syncing = false

            do {
                try await self?.scan()
                try await self?.syncLastBlock()
            } catch {
                self?.handle(error: error)
            }

            self?.syncing = false
        }.erased()
    }

    func terminate() {
        task = nil
    }
}
