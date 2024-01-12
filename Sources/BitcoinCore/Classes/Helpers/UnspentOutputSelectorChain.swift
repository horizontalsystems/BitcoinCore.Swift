class UnspentOutputSelectorChain: IUnspentOutputSelector {
    private let provider: IUnspentOutputProvider
    var concreteSelectors = [IUnspentOutputSelector]()

    init(provider: IUnspentOutputProvider) {
        self.provider = provider
    }

    var all: [UnspentOutput] {
        provider.spendableUtxo
    }

    func select(value: Int, memo: String?, feeRate: Int, outputScriptType: ScriptType, changeType: ScriptType, senderPay: Bool, pluginDataOutputSize: Int) throws -> SelectedUnspentOutputInfo {
        var lastError: Error = BitcoinCoreErrors.Unexpected.unknown

        for selector in concreteSelectors {
            do {
                return try selector.select(value: value, memo: memo, feeRate: feeRate, outputScriptType: outputScriptType, changeType: changeType, senderPay: senderPay, pluginDataOutputSize: pluginDataOutputSize)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    func prepend(unspentOutputSelector: IUnspentOutputSelector) {
        concreteSelectors.insert(unspentOutputSelector, at: 0)
    }
}
