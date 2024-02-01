import Foundation

class TransactionCreator {
    enum CreationError: Error {
        case transactionAlreadyExists
    }

    private let transactionBuilder: ITransactionBuilder
    private let transactionProcessor: IPendingTransactionProcessor
    private let transactionSender: ITransactionSender
    private let bloomFilterManager: IBloomFilterManager
    private let signer: ITransactionSigner

    init(transactionBuilder: ITransactionBuilder, transactionProcessor: IPendingTransactionProcessor, transactionSender: ITransactionSender, bloomFilterManager: IBloomFilterManager, signer: ITransactionSigner) {
        self.transactionBuilder = transactionBuilder
        self.transactionProcessor = transactionProcessor
        self.transactionSender = transactionSender
        self.bloomFilterManager = bloomFilterManager
        self.signer = signer
    }

    private func processAndSend(transaction: FullTransaction) throws {
        try transactionSender.verifyCanSend()

        do {
            try transactionProcessor.processCreated(transaction: transaction)
        } catch _ as BloomFilterManager.BloomFilterExpired {
            bloomFilterManager.regenerateBloomFilter()
        }

        transactionSender.send(pendingTransaction: transaction)
    }
}

extension TransactionCreator: ITransactionCreator {
    func create(to address: String, memo: String?, value: Int, feeRate: Int, senderPay: Bool, sortType: TransactionDataSortType, unspentOutputs: [UnspentOutput]?, pluginData: [UInt8: IPluginData] = [:]) throws -> FullTransaction {
        let transaction = try transactionBuilder.buildTransaction(
            toAddress: address,
            memo: memo,
            value: value,
            feeRate: feeRate,
            senderPay: senderPay,
            sortType: sortType,
            unspentOutputs: unspentOutputs,
            pluginData: pluginData,
            signer: signer
        )

        try processAndSend(transaction: transaction)
        return transaction
    }

    func create(from unspentOutput: UnspentOutput, to address: String, memo: String?, feeRate: Int, sortType: TransactionDataSortType) throws -> FullTransaction {
        let transaction = try transactionBuilder.buildTransaction(
            from: unspentOutput,
            toAddress: address,
            memo: memo,
            feeRate: feeRate,
            sortType: sortType,
            signer: self.signer
        )

        try processAndSend(transaction: transaction)
        return transaction
    }

    func createRawTransaction(to address: String, memo: String?, value: Int, feeRate: Int, senderPay: Bool, sortType: TransactionDataSortType, unspentOutputs: [UnspentOutput]?, pluginData: [UInt8: IPluginData] = [:]) throws -> Data {
        let transaction = try transactionBuilder.buildTransaction(
            toAddress: address,
            memo: memo,
            value: value,
            feeRate: feeRate,
            senderPay: senderPay,
            sortType: sortType,
            unspentOutputs: unspentOutputs,
            pluginData: pluginData,
            signer: self.signer
        )

        return TransactionSerializer.serialize(transaction: transaction)
    }
}
