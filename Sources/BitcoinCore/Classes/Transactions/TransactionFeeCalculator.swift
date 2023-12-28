class TransactionFeeCalculator {
    private let recipientSetter: IRecipientSetter
    private let inputSetter: IInputSetter
    private let addressConverter: IAddressConverter
    private let publicKeyManager: IPublicKeyManager
    private let transactionSizeCalculator: TransactionSizeCalculator
    private let changeScriptType: ScriptType

    init(recipientSetter: IRecipientSetter, inputSetter: IInputSetter, addressConverter: IAddressConverter, publicKeyManager: IPublicKeyManager, transactionSizeCalculator: TransactionSizeCalculator, changeScriptType: ScriptType) {
        self.recipientSetter = recipientSetter
        self.inputSetter = inputSetter
        self.addressConverter = addressConverter
        self.publicKeyManager = publicKeyManager
        self.transactionSizeCalculator = transactionSizeCalculator
        self.changeScriptType = changeScriptType
    }

    private func sampleAddress() throws -> String {
        try addressConverter.convert(publicKey: publicKeyManager.changePublicKey(), type: changeScriptType).stringValue
    }
}

extension TransactionFeeCalculator: ITransactionFeeCalculator {
    func fee(for value: Int, feeRate: Int, senderPay: Bool, toAddress: String?, unspentOutputs: [UnspentOutput]?, pluginData: [UInt8: IPluginData] = [:]) throws -> BitcoinSendInfo {
        let mutableTransaction = MutableTransaction()

        try recipientSetter.setRecipient(to: mutableTransaction, toAddress: toAddress ?? sampleAddress(), value: value, pluginData: pluginData, skipChecks: true)

        let outputs: [UnspentOutput]
        if let unspentOutputs {
            outputs = unspentOutputs
            try inputSetter.setInputs(to: mutableTransaction, feeRate: feeRate, senderPay: senderPay, unspentOutputs: unspentOutputs, sortType: .none)
        } else {
            outputs = try inputSetter.setInputs(to: mutableTransaction, feeRate: feeRate, senderPay: senderPay, sortType: .none)
        }

        let inputsTotalValue = mutableTransaction.inputsToSign.reduce(0) { total, input in total + input.previousOutput.value }
        let outputsTotalValue = mutableTransaction.recipientValue + mutableTransaction.changeValue

        return BitcoinSendInfo(fee: inputsTotalValue - outputsTotalValue, unspentOutputs: outputs)
    }
}
