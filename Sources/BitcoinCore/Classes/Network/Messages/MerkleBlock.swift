import Foundation

public class MerkleBlock {
    let header: BlockHeader
    let transactionHashes: [Data]
    var height: Int?
    var transactions: [FullTransaction]

    lazy var headerHash: Data = self.header.headerHash

    var complete: Bool {
        transactionHashes.count == transactions.count
    }

    init(header: BlockHeader, transactionHashes: [Data], transactions: [FullTransaction]) {
        self.header = header
        self.transactionHashes = transactionHashes
        self.transactions = transactions
    }
}
