class UnspentOutputQueue {
    let params: Parameters
    let sizeCalculator: ITransactionSizeCalculator

    let recipientOutputDust: Int
    let changeOutputDust: Int

    var selectedOutputs = [UnspentOutput]()
    var totalValue = 0

    init(parameters: Parameters, sizeCalculator: ITransactionSizeCalculator, dustCalculator: IDustCalculator, outputs: [UnspentOutput] = []) {
        params = parameters
        self.sizeCalculator = sizeCalculator

        recipientOutputDust = dustCalculator.dust(type: params.outputScriptType)
        changeOutputDust = dustCalculator.dust(type: params.changeType)

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
        let receiveValue = params.senderPay ? value : value - fee
        // should send
        let sentValue = params.senderPay ? value + fee : value

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

        // Calculate the possibility of sending without change
        let feeWithoutChange = sizeCalculator.transactionSize(
            previousOutputs: selectedOutputs.map(\.output),
            outputScriptTypes: [params.outputScriptType],
            memo: params.memo,
            pluginDataOutputSize: params.pluginDataOutputSize
        ) * params.fee

        // Calculate the values with which a transaction can be sent
        let sendValues = try values(value: params.value, total: totalValue, fee: feeWithoutChange)

        // Calculate how much is needed for change
        let changeFee = sizeCalculator.outputSize(type: params.changeType) * params.fee

        // Calculate how much will remain after adding the change
        let remainder = sendValues.remainder - changeFee

        // If this value is less than 'dust', then we'll leave it without change (the remainder will go towards the network fee)
        if remainder <= recipientOutputDust {
            return SelectedUnspentOutputInfo(unspentOutputs: selectedOutputs, recipientValue: sendValues.receive, changeValue: nil)
        }

        return SelectedUnspentOutputInfo(unspentOutputs: selectedOutputs, recipientValue: sendValues.receive, changeValue: remainder)
    }

    struct Parameters {
        let value: Int
        let senderPay: Bool
        let memo: String?
        let fee: Int

        let outputsLimit: Int?

        let outputScriptType: ScriptType
        let changeType: ScriptType

        let pluginDataOutputSize: Int
    }
}
