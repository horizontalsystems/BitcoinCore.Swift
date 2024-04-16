import Foundation

class TransactionCreator {
    enum CreationError: Error {
        case transactionAlreadyExists
    }

    private let transactionBuilder: ITransactionBuilder
    private let transactionProcessor: IPendingTransactionProcessor
    private let transactionSender: ITransactionSender
    private let transactionSigner: TransactionSigner
    private let bloomFilterManager: IBloomFilterManager

    init(transactionBuilder: ITransactionBuilder, transactionProcessor: IPendingTransactionProcessor, transactionSender: ITransactionSender, transactionSigner: TransactionSigner, bloomFilterManager: IBloomFilterManager) {
        self.transactionBuilder = transactionBuilder
        self.transactionProcessor = transactionProcessor
        self.transactionSender = transactionSender
        self.transactionSigner = transactionSigner
        self.bloomFilterManager = bloomFilterManager
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
    func create(params: SendParameters) throws -> FullTransaction {
        let mutableTransaction = try transactionBuilder.buildTransaction(params: params)

        return try create(from: mutableTransaction)
    }

    func create(from unspentOutput: UnspentOutput, params: SendParameters) throws -> FullTransaction {
        let mutableTransaction = try transactionBuilder.buildTransaction(from: unspentOutput, params: params)

        return try create(from: mutableTransaction)
    }

    func create(from mutableTransaction: MutableTransaction) throws -> FullTransaction {
        try transactionSigner.sign(mutableTransaction: mutableTransaction)
        let fullTransaction = mutableTransaction.build()

        try processAndSend(transaction: fullTransaction)
        return fullTransaction
    }

    func createRawTransaction(params: SendParameters) throws -> Data {
        let mutableTransaction = try transactionBuilder.buildTransaction(params: params)
        try transactionSigner.sign(mutableTransaction: mutableTransaction)
        let fullTransaction = mutableTransaction.build()

        return TransactionSerializer.serialize(transaction: fullTransaction)
    }
}
