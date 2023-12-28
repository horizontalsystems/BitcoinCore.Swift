class TransactionFeeCalculator {
    private let recipientSetter: IRecipientSetter
    private let inputSetter: IInputSetter
    private let addressConverter: IAddressConverter
    private let publicKeyManager: IPublicKeyManager
    private let changeScriptType: ScriptType

    init(recipientSetter: IRecipientSetter, inputSetter: IInputSetter, addressConverter: IAddressConverter, publicKeyManager: IPublicKeyManager, changeScriptType: ScriptType) {
        self.recipientSetter = recipientSetter
        self.inputSetter = inputSetter
        self.addressConverter = addressConverter
        self.publicKeyManager = publicKeyManager
        self.changeScriptType = changeScriptType
    }

    private func sampleAddress() throws -> String {
        try addressConverter.convert(publicKey: publicKeyManager.changePublicKey(), type: changeScriptType).stringValue
    }
}

extension TransactionFeeCalculator: ITransactionFeeCalculator {
    func sendInfo(for value: Int, feeRate: Int, senderPay: Bool, toAddress: String?, unspentOutputs: [UnspentOutput]?, pluginData: [UInt8: IPluginData] = [:]) throws -> BitcoinSendInfo {
        let mutableTransaction = MutableTransaction()

        try recipientSetter.setRecipient(to: mutableTransaction, toAddress: toAddress ?? sampleAddress(), value: value, pluginData: pluginData, skipChecks: true)

        let outputInfo = try inputSetter.setInputs(to: mutableTransaction, feeRate: feeRate, senderPay: senderPay, unspentOutputs: unspentOutputs, sortType: .none)

        let inputsTotalValue = mutableTransaction.inputsToSign.reduce(0) { total, input in total + input.previousOutput.value }
        let outputsTotalValue = mutableTransaction.recipientValue + mutableTransaction.changeValue

        return BitcoinSendInfo(
            unspentOutputs: outputInfo.unspentOutputs,
            fee: inputsTotalValue - outputsTotalValue,
            changeValue: outputInfo.changeInfo?.value,
            changeAddress: outputInfo.changeInfo?.address
        )
    }
}
