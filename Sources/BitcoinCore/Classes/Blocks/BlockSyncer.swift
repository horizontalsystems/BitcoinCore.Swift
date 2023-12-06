import Foundation
import HsToolKit

class BlockSyncer {
    weak var listener: IBlockSyncListener?
    private let storage: IStorage

    private let checkpoint: Checkpoint
    private let factory: IFactory
    private let transactionProcessor: IBlockTransactionProcessor
    private let blockchain: IBlockchain
    private let publicKeyManager: IPublicKeyManager

    private let hashCheckpointThreshold: Int
    private var state: BlockSyncerState

    private let logger: Logger?

    init(storage: IStorage, checkpoint: Checkpoint, factory: IFactory, transactionProcessor: IBlockTransactionProcessor,
         blockchain: IBlockchain, publicKeyManager: IPublicKeyManager, hashCheckpointThreshold: Int, logger: Logger?, state: BlockSyncerState)
    {
        self.storage = storage
        self.checkpoint = checkpoint
        self.factory = factory
        self.transactionProcessor = transactionProcessor
        self.blockchain = blockchain
        self.publicKeyManager = publicKeyManager
        self.hashCheckpointThreshold = hashCheckpointThreshold
        self.logger = logger
        self.state = state
    }

    var localDownloadedBestBlockHeight: Int32 {
        let height = storage.lastBlock?.height
        return Int32(height ?? 0)
    }

    var localKnownBestBlockHeight: Int32 {
        let blockchainHashes = storage.blockchainBlockHashes
        let existingHashesCount = storage.blocksCount(headerHashes: blockchainHashes.map(\.headerHash))
        return localDownloadedBestBlockHeight + Int32(blockchainHashes.count - existingHashesCount)
    }

    // We need to clear block hashes when sync peer is disconnected
    private func clearBlockHashes() {
        storage.deleteBlockchainBlockHashes()
    }

    private func clearPartialBlocks() throws {
        var excludedHashes = [checkpoint.block.headerHash]
        checkpoint.additionalBlocks.forEach { excludedHashes.append($0.headerHash) }

        let blockHashes = storage.blockHashHeaderHashes(except: excludedHashes)
        let blocksToDelete = storage.blocks(byHexes: blockHashes)
        let partialBlocksToDelete = blocksToDelete.filter(\.partial)

        try blockchain.deleteBlocks(blocks: partialBlocksToDelete)
    }

    private func handlePartialBlocks() throws {
        try publicKeyManager.fillGap()
        state.iteration(hasPartialBlocks: false)
    }
}

extension BlockSyncer: IBlockSyncer {
    func prepareForDownload() {
        do {
            try handlePartialBlocks()
            try clearPartialBlocks()
            clearBlockHashes()

            try blockchain.handleFork()
        } catch {
            logger?.error(error)
        }
    }

    func downloadStarted() {}

    func downloadIterationCompleted() {
        if state.iterationHasPartialBlocks {
            try? handlePartialBlocks()
        }
    }

    func downloadCompleted() {
        try? blockchain.handleFork()
    }

    func downloadFailed() {
        prepareForDownload()
    }

    func getBlockHashes(limit: Int) -> [BlockHash] {
        storage.blockHashesSortedBySequenceAndHeight(limit: limit)
    }

    func getBlockLocatorHashes(peerLastBlockHeight: Int32) -> [Data] {
        var blockLocatorHashes = [Data]()

        if let lastBlockHash = storage.lastBlockchainBlockHash {
            blockLocatorHashes.append(lastBlockHash.headerHash)
        } else {
            for block in storage.blocks(heightGreaterThan: checkpoint.block.height, sortedBy: Block.Columns.height, limit: 10) {
                blockLocatorHashes.append(block.headerHash)
            }
        }

        if let peerLastBlock = storage.block(byHeight: Int(peerLastBlockHeight)) {
            if !blockLocatorHashes.contains(peerLastBlock.headerHash) {
                blockLocatorHashes.append(peerLastBlock.headerHash)
            }
        } else {
            blockLocatorHashes.append(checkpoint.block.headerHash)
        }

        return blockLocatorHashes
    }

    func add(blockHashes: [Data]) {
        var lastOrder = storage.lastBlockHash?.sequence ?? 0
        let existingHashes = storage.blockHashHeaderHashes

        let blockHashes: [BlockHash] = blockHashes
            .filter {
                !existingHashes.contains($0)
            }.map {
                lastOrder += 1
                return factory.blockHash(withHeaderHash: $0, height: 0, order: lastOrder)
            }

        storage.add(blockHashes: blockHashes)
    }

    func handle(merkleBlock: MerkleBlock, maxBlockHeight: Int32) throws {
        var block: Block!

        if let height = merkleBlock.height {
            block = try blockchain.forceAdd(merkleBlock: merkleBlock, height: height)
        } else {
            block = try blockchain.connect(merkleBlock: merkleBlock)
        }

        do {
            try transactionProcessor.processReceived(transactions: merkleBlock.transactions, inBlock: block, skipCheckBloomFilter: state.iterationHasPartialBlocks)
        } catch _ as BloomFilterManager.BloomFilterExpired {
            state.iteration(hasPartialBlocks: true)
        }

        if state.iterationHasPartialBlocks {
            try storage.setBlockPartial(hash: block.headerHash)
        } else {
            storage.deleteBlockHash(byHash: block.headerHash)
        }

        if merkleBlock.height != nil {
            listener?.blockForceAdded()
        } else {
            listener?.currentBestBlockHeightUpdated(height: Int32(block.height), maxBlockHeight: maxBlockHeight)
        }
    }
}

extension BlockSyncer {
    public static func instance(storage: IStorage, checkpoint: Checkpoint, factory: IFactory,
                                transactionProcessor: IBlockTransactionProcessor, blockchain: IBlockchain, publicKeyManager: IPublicKeyManager,
                                hashCheckpointThreshold: Int = 100, logger: Logger? = nil, state: BlockSyncerState = BlockSyncerState()) -> BlockSyncer
    {
        let syncer = BlockSyncer(storage: storage, checkpoint: checkpoint, factory: factory, transactionProcessor: transactionProcessor,
                                 blockchain: blockchain, publicKeyManager: publicKeyManager, hashCheckpointThreshold: hashCheckpointThreshold, logger: logger, state: state)

        return syncer
    }
}
