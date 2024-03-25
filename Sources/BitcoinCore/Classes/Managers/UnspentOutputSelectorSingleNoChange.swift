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
    public var all: [UnspentOutput] {
        provider.spendableUtxo
    }

    public func select(value: Int, memo: String?, feeRate: Int, outputScriptType: ScriptType = .p2pkh, changeType: ScriptType = .p2pkh, senderPay: Bool, pluginDataOutputSize: Int) throws -> SelectedUnspentOutputInfo {
        let sortedOutputs = provider.spendableUtxo.sorted(by: { lhs, rhs in
            (lhs.output.failedToSpend && !rhs.output.failedToSpend) || (
                lhs.output.failedToSpend == rhs.output.failedToSpend && lhs.output.value < rhs.output.value
            )
        })

        // check if value is not dust. recipientValue may be less, but not more
        guard value >= dustCalculator.dust(type: outputScriptType) else {
            throw BitcoinCoreErrors.SendValueErrors.dust
        }

        let params = UnspentOutputQueue.Parameters(
            value: value,
            senderPay: senderPay,
            memo: memo,
            fee: feeRate,
            outputsLimit: nil,
            outputScriptType: outputScriptType,
            changeType: changeType,
            pluginDataOutputSize: pluginDataOutputSize
        )

        let queue = UnspentOutputQueue(parameters: params, sizeCalculator: calculator, dustCalculator: dustCalculator)

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
