import Foundation

public struct SelectedUnspentOutputInfo {
    public let unspentOutputs: [UnspentOutput]
    public let recipientValue: Int // amount to set to recipient output
    public let changeValue: Int? // amount to set to change output. No change output if nil

    public init(unspentOutputs: [UnspentOutput], recipientValue: Int, changeValue: Int?) {
        self.unspentOutputs = unspentOutputs
        self.recipientValue = recipientValue
        self.changeValue = changeValue
    }
}

public class UnspentOutputSelector {
    private let calculator: ITransactionSizeCalculator
    private let provider: IUnspentOutputProvider
    private let dustCalculator: IDustCalculator
    private let outputsLimit: Int?

    public init(calculator: ITransactionSizeCalculator, provider: IUnspentOutputProvider, dustCalculator: IDustCalculator, outputsLimit: Int? = nil) {
        self.calculator = calculator
        self.provider = provider
        self.dustCalculator = dustCalculator
        self.outputsLimit = outputsLimit
    }
}

extension UnspentOutputSelector: IUnspentOutputSelector {
    public var all: [UnspentOutput] {
        provider.spendableUtxo
    }

    public func select(params: SendParameters, outputScriptType: ScriptType = .p2pkh, changeType: ScriptType = .p2pkh, pluginDataOutputSize: Int) throws -> SelectedUnspentOutputInfo {
        guard let value = params.value else {
            throw BitcoinCoreErrors.TransactionSendError.invalidParameters
        }

        let sortedOutputs = provider.spendableUtxo.sorted(by: { lhs, rhs in
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
            outputsLimit: outputsLimit,
            outputScriptType: outputScriptType,
            changeType: changeType,
            pluginDataOutputSize: pluginDataOutputSize
        )
        let queue = UnspentOutputQueue(parameters: utxoSelectParams, sizeCalculator: calculator, dustCalculator: dustCalculator)

        // select unspentOutputs with least value until we get needed value
        var lastError: Error?
        for unspentOutput in sortedOutputs {
            queue.push(output: unspentOutput)

            do {
                return try queue.calculate()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? BitcoinCoreErrors.SendValueErrors.notEnough
    }
}
