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

class UnspentOutputQueue {
    let params: Parameters
    let sizeCalculator: ITransactionSizeCalculator

    let recipientOutputDust: Int

    var changeOutputDust: Int = 0
    var selectedOutputs = [UnspentOutput]()
    var totalValue = 0

    var changeType: ScriptType {
        var _changeType = params.changeType

        if params.sendParams.changeToFirstInput, let firstOutput = selectedOutputs.first {
            _changeType = firstOutput.output.scriptType
        }

        return _changeType
    }

    init(parameters: Parameters, sizeCalculator: ITransactionSizeCalculator, dustCalculator: IDustCalculator, outputs: [UnspentOutput] = []) {
        params = parameters
        self.sizeCalculator = sizeCalculator

        recipientOutputDust = dustCalculator.dust(type: params.outputScriptType, dustThreshold: parameters.sendParams.dustThreshold)
        changeOutputDust = dustCalculator.dust(type: changeType, dustThreshold: parameters.sendParams.dustThreshold)

        outputs.forEach { push(output: $0) }
    }

    func push(output: UnspentOutput) {
        selectedOutputs.append(output)
        totalValue += output.output.value

        if let limit = params.outputsLimit, limit > 0, selectedOutputs.count > limit {
            totalValue -= selectedOutputs.first?.output.value ?? 0
            selectedOutputs.removeFirst()
        }
    }

    func set(outputs: [UnspentOutput]) {
        selectedOutputs.removeAll()
        totalValue = 0

        outputs.forEach { push(output: $0) }
    }

    // we have the total value of Satoshi outputs as 'totalValue' and the fee required for sending the transaction, alongside the value intended for the recipient
    // we can calculate the amount the user will receive and the potential amount that can be returned to the sender
    private func values(value: Int, total: Int, fee: Int) throws -> (receive: Int, remainder: Int) {
        // will receive
        let receiveValue = params.sendParams.senderPay ? value : value - fee
        // should send
        let sentValue = params.sendParams.senderPay ? value + fee : value

        // If the total value of outputs is less than required, throw notEnough
        if totalValue < sentValue { throw BitcoinCoreErrors.SendValueErrors.notEnough }
        // if receiveValue less than dust, just throw error
        if receiveValue <= recipientOutputDust { throw BitcoinCoreErrors.SendValueErrors.dust }

        // The remainder after sending the required amount to the recipient
        let remainder = total - receiveValue - fee

        return (receive: receiveValue, remainder: remainder)
    }

    func calculate() throws -> SelectedUnspentOutputInfo {
        guard !selectedOutputs.isEmpty else {
            throw BitcoinCoreErrors.SendValueErrors.emptyOutputs
        }
        guard let value = params.sendParams.value, let feeRate = params.sendParams.feeRate else {
            throw BitcoinCoreErrors.TransactionSendError.invalidParameters
        }

        // Calculate the possibility of sending without change
        let feeWithoutChange = sizeCalculator.transactionSize(
            previousOutputs: selectedOutputs.map(\.output),
            outputScriptTypes: [params.outputScriptType],
            memo: params.sendParams.memo,
            pluginDataOutputSize: params.pluginDataOutputSize
        ) * feeRate

        // Calculate the values with which a transaction can be sent
        let sendValues = try values(value: value, total: totalValue, fee: feeWithoutChange)

        // Calculate how much is needed for change
        let changeFee = sizeCalculator.outputSize(type: changeType) * feeRate

        // Calculate how much will remain after adding the change
        let remainder = sendValues.remainder - changeFee

        // If this value is less than 'dust', then we'll leave it without change (the remainder will go towards the network fee)
        if remainder <= recipientOutputDust {
            return SelectedUnspentOutputInfo(unspentOutputs: selectedOutputs, recipientValue: sendValues.receive, changeValue: nil)
        }

        return SelectedUnspentOutputInfo(unspentOutputs: selectedOutputs, recipientValue: sendValues.receive, changeValue: remainder)
    }

    struct Parameters {
        let sendParams: SendParameters

        let outputsLimit: Int?

        let outputScriptType: ScriptType
        let changeType: ScriptType

        let pluginDataOutputSize: Int
    }
}
