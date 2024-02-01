class TransactionBuilder {
    private let recipientSetter: IRecipientSetter
    private let inputSetter: IInputSetter
    private let lockTimeSetter: ILockTimeSetter
    private let outputSetter: IOutputSetter

    init(recipientSetter: IRecipientSetter, inputSetter: IInputSetter, lockTimeSetter: ILockTimeSetter, outputSetter: IOutputSetter, signer: ITransactionSigner) {
        self.recipientSetter = recipientSetter
        self.inputSetter = inputSetter
        self.lockTimeSetter = lockTimeSetter
        self.outputSetter = outputSetter
    }
}

extension TransactionBuilder: ITransactionBuilder {
    func buildTransaction(toAddress: String, memo: String?, value: Int, feeRate: Int, senderPay: Bool, sortType: TransactionDataSortType, unspentOutputs: [UnspentOutput]?, pluginData: [UInt8: IPluginData], signer: ITransactionSigner) throws -> FullTransaction {
        let mutableTransaction = MutableTransaction()

        try recipientSetter.setRecipient(to: mutableTransaction, toAddress: toAddress, memo: memo, value: value, pluginData: pluginData, skipChecks: false)
        try inputSetter.setInputs(to: mutableTransaction, feeRate: feeRate, senderPay: senderPay, unspentOutputs: unspentOutputs, sortType: sortType)
        lockTimeSetter.setLockTime(to: mutableTransaction)

        outputSetter.setOutputs(to: mutableTransaction, sortType: sortType)
        try signer.sign(mutableTransaction: mutableTransaction)

        return mutableTransaction.build()
    }

    func buildTransaction(from unspentOutput: UnspentOutput, toAddress: String, memo: String?, feeRate: Int, sortType: TransactionDataSortType, signer: ITransactionSigner) throws -> FullTransaction {
        let mutableTransaction = MutableTransaction(outgoing: false)

        try recipientSetter.setRecipient(to: mutableTransaction, toAddress: toAddress, memo: memo, value: unspentOutput.output.value, pluginData: [:], skipChecks: false)
        try inputSetter.setInputs(to: mutableTransaction, fromUnspentOutput: unspentOutput, feeRate: feeRate)
        lockTimeSetter.setLockTime(to: mutableTransaction)

        outputSetter.setOutputs(to: mutableTransaction, sortType: sortType)
        try signer.sign(mutableTransaction: mutableTransaction)

        return mutableTransaction.build()
    }
}
