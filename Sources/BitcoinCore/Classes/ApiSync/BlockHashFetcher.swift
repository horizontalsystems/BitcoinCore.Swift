import Foundation

public class BlockHashFetcher: IBlockHashFetcher {
    private let hsFetcher: HsBlockHashFetcher
    private let blockchairFetcher: BlockchairBlockHashFetcher
    private let checkpointHeight: Int

    public init(hsFetcher: HsBlockHashFetcher, blockchairFetcher: BlockchairBlockHashFetcher, checkpointHeight: Int) {
        self.hsFetcher = hsFetcher
        self.blockchairFetcher = blockchairFetcher
        self.checkpointHeight = checkpointHeight
    }

    public func fetch(heights: [Int]) async throws -> [Int: String] {
        let sorted = heights.sorted()
        let beforeCheckpoint = sorted.filter { $0 <= checkpointHeight }
        let afterCheckpoint = Array(sorted.suffix(sorted.count - beforeCheckpoint.count))

        var blockHashes = [Int: String]()

        if beforeCheckpoint.count > 0 {
            blockHashes = try await hsFetcher.fetch(heights: beforeCheckpoint)
        }

        if afterCheckpoint.count > 0 {
            try await blockHashes.merge(blockchairFetcher.fetch(heights: afterCheckpoint), uniquingKeysWith: { a, _ in a })
        }

        return blockHashes
    }
}
