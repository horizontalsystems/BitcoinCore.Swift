class UnspentOutputSelectorChain: IUnspentOutputSelector {
    private let provider: IUnspentOutputProvider
    var concreteSelectors = [IUnspentOutputSelector]()

    init(provider: IUnspentOutputProvider) {
        self.provider = provider
    }

    var all: [UnspentOutput] {
        provider.spendableUtxo
    }

    func select(params: SendParameters, outputScriptType: ScriptType, changeType: ScriptType, pluginDataOutputSize: Int) throws -> SelectedUnspentOutputInfo {
        var lastError: Error = BitcoinCoreErrors.Unexpected.unknown

        for selector in concreteSelectors {
            do {
                return try selector.select(params: params, outputScriptType: outputScriptType, changeType: changeType, pluginDataOutputSize: pluginDataOutputSize)
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
