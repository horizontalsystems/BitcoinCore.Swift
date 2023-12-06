class TransactionExtractor {
    private let outputScriptTypeParser: ITransactionExtractor
    private let publicKeySetter: ITransactionExtractor
    private let inputExtractor: ITransactionExtractor
    private let outputAddressExtractor: ITransactionExtractor
    private let metaDataExtractor: ITransactionExtractor
    private let pluginManager: IPluginManager

    init(outputScriptTypeParser: ITransactionExtractor, publicKeySetter: ITransactionExtractor, inputExtractor: ITransactionExtractor, metaDataExtractor: ITransactionExtractor, outputAddressExtractor: ITransactionExtractor, pluginManager: IPluginManager) {
        self.outputScriptTypeParser = outputScriptTypeParser
        self.publicKeySetter = publicKeySetter
        self.inputExtractor = inputExtractor
        self.outputAddressExtractor = outputAddressExtractor
        self.metaDataExtractor = metaDataExtractor
        self.pluginManager = pluginManager
    }
}

extension TransactionExtractor: ITransactionExtractor {
    func extract(transaction: FullTransaction) {
        outputScriptTypeParser.extract(transaction: transaction)
        publicKeySetter.extract(transaction: transaction)

        if let nullDataOutput = transaction.outputs.last(where: { $0.scriptType == .nullData }) {
            try? pluginManager.processTransactionWithNullData(transaction: transaction, nullDataOutput: nullDataOutput)
        }

        metaDataExtractor.extract(transaction: transaction)

        if transaction.header.isMine {
            outputAddressExtractor.extract(transaction: transaction)
            inputExtractor.extract(transaction: transaction)
        }
    }
}
