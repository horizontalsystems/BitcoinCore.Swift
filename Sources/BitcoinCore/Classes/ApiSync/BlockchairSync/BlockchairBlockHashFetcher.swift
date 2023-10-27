public class BlockchairBlockHashFetcher: IBlockHashFetcher {
    private let blockchairApi: BlockchairApi

    public init(blockchairApi: BlockchairApi) {
        self.blockchairApi = blockchairApi
    }

    public func fetch(heights: [Int]) async throws -> [Int: String] {
        try await blockchairApi.blockHashes(heights: heights)
    }
}
