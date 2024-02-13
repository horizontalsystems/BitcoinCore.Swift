public struct ReplacementTransaction {
    let mutableTransaction: MutableTransaction
    public let info: TransactionInfo
    public let descendantTransactionHashes: [String]
}
