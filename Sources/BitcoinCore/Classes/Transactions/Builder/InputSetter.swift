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
    private let changeType: ScriptType
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
        changeType = changeScriptType
        self.inputSorterFactory = inputSorterFactory
    }

    private func input(fromUnspentOutput unspentOutput: UnspentOutput, rbfEnabled: Bool) throws -> InputToSign {
        // Maximum nSequence value (0xFFFFFFFF) disables nLockTime.
        // According to BIP-125, any value less than 0xFFFFFFFE makes a Replace-by-Fee(RBF) opted in.
        let sequence = rbfEnabled ? 0x0 : 0xFFFF_FFFE

        return factory.inputToSign(withPreviousOutput: unspentOutput, script: Data(), sequence: sequence)
    }
}

extension InputSetter: IInputSetter {
    @discardableResult func setInputs(to mutableTransaction: MutableTransaction, params: SendParameters) throws -> OutputInfo {
        let unspentOutputInfo: SelectedUnspentOutputInfo
        if let unspentOutputs = params.unspentOutputs.flatMap({ $0.outputs(from: unspentOutputSelector.allSpendable(filters: params.utxoFilters)) }) {
            let utxoSelectorParams = UnspentOutputQueue.Parameters(
                sendParams: params,
                outputsLimit: nil,
                outputScriptType: mutableTransaction.recipientAddress.scriptType,
                changeType: changeType,
                pluginDataOutputSize: mutableTransaction.pluginDataOutputSize
            )

            let queue = UnspentOutputQueue(parameters: utxoSelectorParams, sizeCalculator: transactionSizeCalculator, dustCalculator: dustCalculator, outputs: unspentOutputs)
            unspentOutputInfo = try queue.calculate()
        } else {
            unspentOutputInfo = try unspentOutputSelector.select(
                params: params,
                outputScriptType: mutableTransaction.recipientAddress.scriptType,
                changeType: changeType,
                pluginDataOutputSize: mutableTransaction.pluginDataOutputSize
            )
        }

        let unspentOutputs = inputSorterFactory.sorter(for: params.sortType).sort(unspentOutputs: unspentOutputInfo.unspentOutputs)

        for unspentOutput in unspentOutputs {
            try mutableTransaction.add(inputToSign: input(fromUnspentOutput: unspentOutput, rbfEnabled: params.rbfEnabled))
        }

        mutableTransaction.recipientValue = unspentOutputInfo.recipientValue

        // Add change output if needed
        var changeInfo: ChangeInfo?
        if let changeValue = unspentOutputInfo.changeValue {
            let changeAddress: Address

            if params.changeToFirstInput, let firstOutput = unspentOutputInfo.unspentOutputs.first {
                changeAddress = try addressConverter.convert(publicKey: firstOutput.publicKey, type: firstOutput.output.scriptType)
            } else {
                let changePubKey = try publicKeyManager.changePublicKey()
                changeAddress = try addressConverter.convert(publicKey: changePubKey, type: changeType)
            }

            mutableTransaction.changeAddress = changeAddress
            mutableTransaction.changeValue = changeValue
            changeInfo = ChangeInfo(address: changeAddress, value: changeValue)
        }

        try pluginManager.processInputs(mutableTransaction: mutableTransaction)
        return OutputInfo(unspentOutputs: unspentOutputs, changeInfo: changeInfo)
    }

    func setInputs(to mutableTransaction: MutableTransaction, fromUnspentOutput unspentOutput: UnspentOutput, params: SendParameters) throws {
        guard unspentOutput.output.scriptType == .p2sh else {
            throw UnspentOutputError.notSupportedScriptType
        }

        guard let feeRate = params.feeRate else {
            throw BitcoinCoreErrors.TransactionSendError.invalidParameters
        }

        // Calculate fee
        let transactionSize = transactionSizeCalculator.transactionSize(previousOutputs: [unspentOutput.output], outputScriptTypes: [mutableTransaction.recipientAddress.scriptType], memo: mutableTransaction.memo, pluginDataOutputSize: 0)
        let fee = transactionSize * feeRate

        guard fee < unspentOutput.output.value else {
            throw UnspentOutputError.feeMoreThanValue
        }

        // Add to mutable transaction
        try mutableTransaction.add(inputToSign: input(fromUnspentOutput: unspentOutput, rbfEnabled: params.rbfEnabled))
        mutableTransaction.recipientValue = unspentOutput.output.value - fee
    }
}

extension InputSetter {
    public struct ChangeInfo {
        let address: Address
        let value: Int
    }

    public struct OutputInfo {
        let unspentOutputs: [UnspentOutput]
        let changeInfo: ChangeInfo?
    }
}
