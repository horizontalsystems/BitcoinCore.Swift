class RecipientSetter {
    private let addressConverter: IAddressConverter
    private let pluginManager: IPluginManager

    init(addressConverter: IAddressConverter, pluginManager: IPluginManager) {
        self.addressConverter = addressConverter
        self.pluginManager = pluginManager
    }
}

extension RecipientSetter: IRecipientSetter {
    func setRecipient(to mutableTransaction: MutableTransaction, params: SendParameters, skipChecks: Bool = false) throws {
        guard let address = params.address, let value = params.value else {
            throw BitcoinCoreErrors.TransactionSendError.invalidParameters
        }

        mutableTransaction.recipientAddress = try addressConverter.convert(address: address)
        mutableTransaction.recipientValue = value
        mutableTransaction.memo = params.memo

        try pluginManager.processOutputs(mutableTransaction: mutableTransaction, pluginData: params.pluginData, skipChecks: skipChecks)
    }
}
