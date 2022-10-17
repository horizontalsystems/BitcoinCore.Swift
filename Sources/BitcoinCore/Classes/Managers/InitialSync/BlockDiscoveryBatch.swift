import Foundation
import RxSwift
import ObjectMapper
import HsToolKit

class BlockDiscoveryBatch {
    private let blockHashFetcher: IBlockHashFetcher
    private let publicKeyFetcher: IPublicKeyFetcher

    private let maxHeight: Int
    private let gapLimit: Int

    init(checkpoint: Checkpoint, gapLimit: Int, blockHashFetcher: IBlockHashFetcher, publicKeyFetcher: IPublicKeyFetcher, logger: Logger? = nil) {
        self.blockHashFetcher = blockHashFetcher
        self.publicKeyFetcher = publicKeyFetcher

        maxHeight = checkpoint.block.height
        self.gapLimit = gapLimit
    }

    private func fetchRecursive(blockHashes: [BlockHash] = [], externalBatchInfo: KeyBlockHashBatchInfo = KeyBlockHashBatchInfo(), internalBatchInfo: KeyBlockHashBatchInfo = KeyBlockHashBatchInfo()) -> Single<([PublicKey], [BlockHash])> {
        let maxHeight = maxHeight

        let externalCount = gapLimit - externalBatchInfo.prevCount + externalBatchInfo.prevLastUsedIndex + 1
        let internalCount = gapLimit - internalBatchInfo.prevCount + internalBatchInfo.prevLastUsedIndex + 1

        var externalNewKeys = [PublicKey]()
        var internalNewKeys = [PublicKey]()

        do {
            externalNewKeys.append(contentsOf: try publicKeyFetcher.publicKeys(indices: UInt32(externalBatchInfo.startIndex)..<UInt32(externalBatchInfo.startIndex + externalCount), external: true))
            internalNewKeys.append(contentsOf: try publicKeyFetcher.publicKeys(indices: UInt32(internalBatchInfo.startIndex)..<UInt32(internalBatchInfo.startIndex + internalCount), external: false))
        } catch {
            return Single.error(error)
        }

        return blockHashFetcher.getBlockHashes(externalKeys: externalNewKeys, internalKeys: internalNewKeys).flatMap { [weak self] fetcherResponse -> Single<([PublicKey], [BlockHash])> in
            let resultBlockHashes = blockHashes + fetcherResponse.blockHashes.filter { $0.height <= maxHeight }
            let externalPublicKeys = externalBatchInfo.publicKeys + externalNewKeys
            let internalPublicKeys = internalBatchInfo.publicKeys + internalNewKeys

            let finishSingle = Single.just((externalPublicKeys + internalPublicKeys, resultBlockHashes))

            if fetcherResponse.externalLastUsedIndex < 0 && fetcherResponse.internalLastUsedIndex < 0 {
                return finishSingle
            } else {
                let externalBatch = KeyBlockHashBatchInfo(publicKeys: externalPublicKeys, prevCount: externalCount, prevLastUsedIndex: fetcherResponse.externalLastUsedIndex, startIndex: externalBatchInfo.startIndex + externalCount)
                let internalBatch = KeyBlockHashBatchInfo(publicKeys: internalPublicKeys, prevCount: internalCount, prevLastUsedIndex: fetcherResponse.internalLastUsedIndex, startIndex: internalBatchInfo.startIndex + internalCount)

                return self?.fetchRecursive(blockHashes: resultBlockHashes, externalBatchInfo: externalBatch, internalBatchInfo: internalBatch) ?? finishSingle
            }
        }
    }

}

extension BlockDiscoveryBatch: IBlockDiscovery {

    func discoverBlockHashes() -> Single<([PublicKey], [BlockHash])> {
        fetchRecursive()
    }

}

class KeyBlockHashBatchInfo {
    var publicKeys: [PublicKey]
    var prevCount: Int
    var prevLastUsedIndex: Int
    var startIndex: Int

    init(publicKeys: [PublicKey] = [], prevCount: Int = 0, prevLastUsedIndex: Int = -1, startIndex: Int = 0) {
        self.publicKeys = publicKeys
        self.prevCount = prevCount
        self.prevLastUsedIndex = prevLastUsedIndex
        self.startIndex = startIndex
    }

}
