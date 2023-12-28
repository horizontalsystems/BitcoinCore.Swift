import Foundation

class InputSetter {
    enum UnspentOutputError: Error {
        case feeMoreThanValue
        case notSupportedScriptType
    }

    private let unspentOutputSelector: IUnspentOutputSelector
    private let transactionSizeCalculator: ITransactionSizeCalculator
    private let addressConverter: IAddressConverter
    private let publicKeyManager: IPublicKeyManager
    private let factory: IFactory
    private let pluginManager: IPluginManager
    private let dustCalculator: IDustCalculator
    private let changeScriptType: ScriptType
    private let inputSorterFactory: ITransactionDataSorterFactory

    init(unspentOutputSelector: IUnspentOutputSelector, transactionSizeCalculator: ITransactionSizeCalculator, addressConverter: IAddressConverter, publicKeyManager: IPublicKeyManager,
         factory: IFactory, pluginManager: IPluginManager, dustCalculator: IDustCalculator, changeScriptType: ScriptType, inputSorterFactory: ITransactionDataSorterFactory)
    {
        self.unspentOutputSelector = unspentOutputSelector
        self.transactionSizeCalculator = transactionSizeCalculator
        self.addressConverter = addressConverter
        self.publicKeyManager = publicKeyManager
        self.factory = factory
        self.pluginManager = pluginManager
        self.dustCalculator = dustCalculator
        self.changeScriptType = changeScriptType
        self.inputSorterFactory = inputSorterFactory
    }

    private func input(fromUnspentOutput unspentOutput: UnspentOutput) throws -> InputToSign {
        // Maximum nSequence value (0xFFFFFFFF) disables nLockTime.
        // According to BIP-125, any value less than 0xFFFFFFFE makes a Replace-by-Fee(RBF) opted in.
        let sequence = 0xFFFF_FFFE

        return factory.inputToSign(withPreviousOutput: unspentOutput, script: Data(), sequence: sequence)
    }
}

extension InputSetter: IInputSetter {
    private func _set(to mutableTransaction: MutableTransaction, unspentOutputInfo: SelectedUnspentOutputInfo, sortType: TransactionDataSortType) throws {
        let unspentOutputs = inputSorterFactory.sorter(for: sortType).sort(unspentOutputs: unspentOutputInfo.unspentOutputs)

        for unspentOutput in unspentOutputs {
            try mutableTransaction.add(inputToSign: input(fromUnspentOutput: unspentOutput))
        }

        mutableTransaction.recipientValue = unspentOutputInfo.recipientValue

        // Add change output if needed
        if let changeValue = unspentOutputInfo.changeValue {
            let changePubKey = try publicKeyManager.changePublicKey()
            let changeAddress = try addressConverter.convert(publicKey: changePubKey, type: changeScriptType)

            mutableTransaction.changeAddress = changeAddress
            mutableTransaction.changeValue = changeValue
        }

        try pluginManager.processInputs(mutableTransaction: mutableTransaction)
    }

    func setInputs(to mutableTransaction: MutableTransaction, feeRate: Int, senderPay: Bool, unspentOutputs: [UnspentOutput], sortType: TransactionDataSortType) throws {
        let params = UnspentOutputQueue.Parameters(
                value: mutableTransaction.recipientValue,
                senderPay: senderPay,
                fee: feeRate,
                outputsLimit: nil,
                outputScriptType: mutableTransaction.recipientAddress.scriptType,
                changeType: changeScriptType,
                pluginDataOutputSize: mutableTransaction.pluginDataOutputSize
        )

        let queue = UnspentOutputQueue(parameters: params, sizeCalculator: transactionSizeCalculator, dustCalculator: dustCalculator, outputs: unspentOutputs)
        let unspentOutputInfo = try queue.calculate()

        try _set(to: mutableTransaction, unspentOutputInfo: unspentOutputInfo, sortType: sortType)
    }

    @discardableResult func setInputs(to mutableTransaction: MutableTransaction, feeRate: Int, senderPay: Bool, sortType: TransactionDataSortType) throws -> [UnspentOutput] {
        let value = mutableTransaction.recipientValue
        let unspentOutputInfo = try unspentOutputSelector.select(
            value: value, feeRate: feeRate,
            outputScriptType: mutableTransaction.recipientAddress.scriptType, changeType: changeScriptType,
            senderPay: senderPay, pluginDataOutputSize: mutableTransaction.pluginDataOutputSize
        )

        try _set(to: mutableTransaction, unspentOutputInfo: unspentOutputInfo, sortType: sortType)
        return unspentOutputInfo.unspentOutputs
    }

    func setInputs(to mutableTransaction: MutableTransaction, fromUnspentOutput unspentOutput: UnspentOutput, feeRate: Int) throws {
        guard unspentOutput.output.scriptType == .p2sh else {
            throw UnspentOutputError.notSupportedScriptType
        }

        // Calculate fee
        let transactionSize = transactionSizeCalculator.transactionSize(previousOutputs: [unspentOutput.output], outputScriptTypes: [mutableTransaction.recipientAddress.scriptType], pluginDataOutputSize: 0)
        let fee = transactionSize * feeRate

        guard fee < unspentOutput.output.value else {
            throw UnspentOutputError.feeMoreThanValue
        }

        // Add to mutable transaction
        try mutableTransaction.add(inputToSign: input(fromUnspentOutput: unspentOutput))
        mutableTransaction.recipientValue = unspentOutput.output.value - fee
    }
}
