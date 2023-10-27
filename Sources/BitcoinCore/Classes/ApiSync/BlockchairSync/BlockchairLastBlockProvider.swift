public class BlockchairLastBlockProvider {
    private let blockchairApi: BlockchairApi

    public init(blockchairApi: BlockchairApi) {
        self.blockchairApi = blockchairApi
    }

    public func lastBlockHeader() async throws -> ApiBlockHeaderItem {
        try await blockchairApi.lastBlockHeader()
    }
}
