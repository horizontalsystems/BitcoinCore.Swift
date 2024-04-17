import Foundation

public class UnspentOutputSelectorSingleNoChange {
    private let calculator: ITransactionSizeCalculator
    private let provider: IUnspentOutputProvider
    private let dustCalculator: IDustCalculator

    public init(calculator: ITransactionSizeCalculator, provider: IUnspentOutputProvider, dustCalculator: IDustCalculator) {
        self.calculator = calculator
        self.provider = provider
        self.dustCalculator = dustCalculator
    }
}

extension UnspentOutputSelectorSingleNoChange: IUnspentOutputSelector {
    public func all(filters: UtxoFilters) -> [UnspentOutput] {
        provider.spendableUtxo(filters: filters)
    }

    public func select(params: SendParameters, outputScriptType: ScriptType = .p2pkh, changeType: ScriptType = .p2pkh, pluginDataOutputSize: Int) throws -> SelectedUnspentOutputInfo {
        guard let value = params.value else {
            throw BitcoinCoreErrors.TransactionSendError.invalidParameters
        }

        let sortedOutputs = all(filters: params.utxoFilters).sorted(by: { lhs, rhs in
            (lhs.output.failedToSpend && !rhs.output.failedToSpend) || (
                lhs.output.failedToSpend == rhs.output.failedToSpend && lhs.output.value < rhs.output.value
            )
        })

        // check if value is not dust. recipientValue may be less, but not more
        guard value >= dustCalculator.dust(type: outputScriptType, dustThreshold: params.dustThreshold) else {
            throw BitcoinCoreErrors.SendValueErrors.dust
        }

        let utxoSelectParams = UnspentOutputQueue.Parameters(
            sendParams: params,
            outputsLimit: nil,
            outputScriptType: outputScriptType,
            changeType: changeType,
            pluginDataOutputSize: pluginDataOutputSize
        )

        let queue = UnspentOutputQueue(parameters: utxoSelectParams, sizeCalculator: calculator, dustCalculator: dustCalculator)

        // select unspentOutputs with least value until we get needed value
        for unspentOutput in sortedOutputs {
            queue.set(outputs: [unspentOutput])

            do {
                let info = try queue.calculate()
                if info.changeValue == nil {
                    return info
                }
            } catch {
                print(error)
            }
        }
        throw BitcoinCoreErrors.SendValueErrors.singleNoChangeOutputNotFound
    }
}
