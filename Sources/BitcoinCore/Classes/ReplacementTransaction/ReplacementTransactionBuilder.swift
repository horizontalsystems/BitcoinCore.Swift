import Foundation

class ReplacementTransactionBuilder {
    private let storage: IStorage
    private let sizeCalculator: ITransactionSizeCalculator
    private let dustCalculator: IDustCalculator
    private let factory: IFactory
    private let metadataExtractor: TransactionMetadataExtractor
    private let pluginManager: IPluginManager

    init(storage: IStorage, sizeCalculator: ITransactionSizeCalculator, dustCalculator: IDustCalculator, factory: IFactory, metadataExtractor: TransactionMetadataExtractor, pluginManager: IPluginManager) {
        self.storage = storage
        self.sizeCalculator = sizeCalculator
        self.dustCalculator = dustCalculator
        self.factory = factory
        self.metadataExtractor = metadataExtractor
        self.pluginManager = pluginManager
    }

    private func replacementTransaction(minFee: Int, minFeeRate: Int, utxo: [Output], fixedOutputs: [Output], outputs: [Output]) -> (outputs: [Output], fee: Int)? {
        var minFee = minFee
        var outputs = outputs

        let size = sizeCalculator.transactionSize(
            previousOutputs: utxo,
            outputs: fixedOutputs + outputs
        )

        let inputsValue = utxo.reduce(into: 0) { acc, out in acc = acc + out.value }
        let outputsValue = (fixedOutputs + outputs).reduce(into: 0) { acc, out in acc = acc + out.value }
        let fee = inputsValue - outputsValue
        let feeRate = fee / size

        if feeRate < minFeeRate {
            minFee = minFeeRate * size
        }

        if fee >= minFee {
            return (outputs: outputs, fee: fee)
        }

        guard outputs.count > 0 else {
            return nil
        }

        let output = Output(original: outputs.removeFirst())
        output.value = output.value - (minFee - fee)

        guard output.value > dustCalculator.dust(type: output.scriptType) else {
            return nil
        }

        return (outputs: [output] + outputs, fee: fee)
    }

    private func unspentOutput(from inputWithPreviousOutput: InputWithPreviousOutput) throws -> UnspentOutput {
        guard let previousOutput = inputWithPreviousOutput.previousOutput,
              let path = inputWithPreviousOutput.previousOutput?.publicKeyPath,
              let publicKey = storage.publicKey(byPath: path),
              let transaction = storage.transaction(byHash: previousOutput.transactionHash)
        else {
            throw BuildError.invalidTransaction
        }

        return UnspentOutput(output: previousOutput, publicKey: publicKey, transaction: transaction)
    }

    private func incrementedSequence(of input: Input) -> Int {
        input.sequence + 1 // TODO: increment locked inputs sequence
    }

    private func setInputs(to mutableTransaction: MutableTransaction, originalInputs: [InputWithPreviousOutput], additionalInputs: [UnspentOutput]) throws {
        mutableTransaction.inputsToSign = additionalInputs.map { utxo in
            factory.inputToSign(withPreviousOutput: utxo, script: Data(), sequence: 0x0)
        }

        try pluginManager.processInputs(mutableTransaction: mutableTransaction)

        let originalInputsToSign = try originalInputs.map { inputWithPreviousOutput in
            let unspentOutput = try unspentOutput(from: inputWithPreviousOutput)
            return factory.inputToSign(
                withPreviousOutput: unspentOutput, script: Data(),
                sequence: incrementedSequence(of: inputWithPreviousOutput.input)
            )
        }

        mutableTransaction.inputsToSign += originalInputsToSign
    }

    private func setOutputs(to mutableTransaction: MutableTransaction, outputs: [Output]) {
        let sorted = ShuffleSorter().sort(outputs: outputs)
        for (index, transactionOutput) in sorted.enumerated() {
            transactionOutput.index = index
        }

        mutableTransaction.outputs = sorted
    }

    private func speedUpReplacement(originalFullInfo: FullTransactionForInfo, minFee: Int, originalFeeRate: Int, fixedUtxo: [Output]) throws -> MutableTransaction? {
        // If an output has a pluginId, it most probably has a timelocked value and it shouldn't be altered.
        let fixedOutputs = originalFullInfo.outputs.filter { $0.publicKeyPath == nil || $0.pluginId != nil }
        let myOutputs = originalFullInfo.outputs.filter { $0.publicKeyPath != nil && $0.pluginId == nil }
        let myChangeOutputs = myOutputs.filter { $0.changeOutput }.sorted { a, b in a.value < b.value }
        let myExternalOutputs = myOutputs.filter { !$0.changeOutput }.sorted { a, b in a.value < b.value }

        let sortedOutputs = myChangeOutputs + myExternalOutputs
        let unusedUtxo = storage.unspentOutputs().sorted(by: { a, b in a.output.value < b.output.value })
        var optimalReplacement: (inputs: [UnspentOutput], outputs: [Output], fee: Int)?

        for utxoCount in 0..<unusedUtxo.count {
            for i in 0..<sortedOutputs.count {
                let utxo = Array(unusedUtxo.prefix(utxoCount))
                let outputsCount = sortedOutputs.count - i
                let outputs = Array(sortedOutputs.suffix(outputsCount))

                if let replacement = replacementTransaction(
                    minFee: minFee, minFeeRate: originalFeeRate,
                    utxo: fixedUtxo + utxo.map { $0.output },
                    fixedOutputs: fixedOutputs, outputs: outputs
                ) {
                    if let _optimalReplacement = optimalReplacement {
                        if _optimalReplacement.fee > replacement.fee {
                            optimalReplacement = (inputs: utxo, outputs: replacement.outputs, fee: replacement.fee)
                        }
                    } else {
                        optimalReplacement = (inputs: utxo, outputs: replacement.outputs, fee: replacement.fee)
                    }
                }
            }
        }

        guard let optimalReplacement else {
            return nil
        }

        let mutableTransaction = MutableTransaction(outgoing: true)

        try setInputs(to: mutableTransaction, originalInputs: originalFullInfo.inputsWithPreviousOutputs, additionalInputs: optimalReplacement.inputs)
        setOutputs(to: mutableTransaction, outputs: fixedOutputs + optimalReplacement.outputs)

        return mutableTransaction
    }

    private func cancelReplacement(originalFullInfo: FullTransactionForInfo, minFee: Int, originalFee: Int, originalFeeRate: Int, fixedUtxo: [Output], changeAddress: Address) throws -> MutableTransaction? {
        let unusedUtxo = storage.unspentOutputs().sorted(by: { a, b in a.output.value < b.output.value })
        let originalInputsValue = fixedUtxo.reduce(into: 0) { acc, out in acc = acc + out.value }
        var optimalReplacement: (inputs: [UnspentOutput], outputs: [Output], fee: Int)?

        for utxoCount in 0..<unusedUtxo.count {
            let utxo = Array(unusedUtxo.prefix(utxoCount))
            let outputs = [factory.output(withIndex: 0, address: changeAddress, value: originalInputsValue - originalFee, publicKey: nil)]

            if let replacement = replacementTransaction(
                minFee: minFee, minFeeRate: originalFeeRate,
                utxo: fixedUtxo + utxo.map { $0.output },
                fixedOutputs: [], outputs: outputs
            ) {
                if let _optimalReplacement = optimalReplacement {
                    if _optimalReplacement.fee > replacement.fee {
                        optimalReplacement = (inputs: utxo, outputs: replacement.outputs, fee: replacement.fee)
                    }
                } else {
                    optimalReplacement = (inputs: utxo, outputs: replacement.outputs, fee: replacement.fee)
                }
            }
        }

        guard let optimalReplacement else {
            return nil
        }

        let mutableTransaction = MutableTransaction(outgoing: true)

        try setInputs(to: mutableTransaction, originalInputs: originalFullInfo.inputsWithPreviousOutputs, additionalInputs: optimalReplacement.inputs)
        setOutputs(to: mutableTransaction, outputs: optimalReplacement.outputs)

        return mutableTransaction
    }

    func replacementTransaction(transactionHash: String, minFee: Int, type: ReplacementType) throws -> (MutableTransaction, FullTransactionForInfo, [String]) {
        guard let transactionHash = transactionHash.hs.hexData,
              let originalFullInfo = storage.transactionFullInfo(byHash: transactionHash),
              originalFullInfo.transactionWithBlock.blockHeight == nil,
              let originalFee = originalFullInfo.metaData.fee,
              originalFullInfo.metaData.type == .outgoing
        else {
            throw BuildError.invalidTransaction
        }

        let fixedUtxo = originalFullInfo.inputsWithPreviousOutputs.compactMap { $0.previousOutput }
        guard fixedUtxo.count == originalFullInfo.inputsWithPreviousOutputs.count else {
            throw BuildError.noPreviousOutput
        }

        guard originalFullInfo.inputsWithPreviousOutputs.contains(where: { $0.input.rbfEnabled }) else {
            throw BuildError.rbfNotEnabled
        }

        let originalSize = sizeCalculator.transactionSize(
            previousOutputs: fixedUtxo,
            outputs: originalFullInfo.outputs
        )

        let originalFeeRate = Int(originalFee / originalSize)
        let descendantTransactions = storage.descendantTransactionsFullInfo(of: transactionHash)
        let descendantTransactionsFee = descendantTransactions
            .map { $0.metaData.fee ?? 0 }
            .reduce(into: 0) { acc, fee in acc = acc + fee }
        let absoluteFee = originalFee + descendantTransactionsFee

        guard absoluteFee <= minFee else {
            throw BuildError.feeTooLow
        }

        var mutableTransaction: MutableTransaction?
        switch type {
            case .speedUp:
                mutableTransaction = try speedUpReplacement(originalFullInfo: originalFullInfo, minFee: minFee, originalFeeRate: originalFeeRate, fixedUtxo: fixedUtxo)
            case .cancel(let changeAddress):
                mutableTransaction = try cancelReplacement(originalFullInfo: originalFullInfo, minFee: minFee, originalFee: originalFee, originalFeeRate: originalFeeRate, fixedUtxo: fixedUtxo, changeAddress: changeAddress)
        }

        guard let mutableTransaction else {
            throw BuildError.unableToReplace
        }

        let fullTransaction = mutableTransaction.build()
        metadataExtractor.extract(transaction: fullTransaction)
        let metadata = fullTransaction.metaData

        return (
            mutableTransaction,
            FullTransactionForInfo(
                transactionWithBlock: TransactionWithBlock(
                    transaction: mutableTransaction.transaction,
                    blockHeight: nil
                ),
                inputsWithPreviousOutputs: mutableTransaction.inputsToSign.map { inputToSign in
                    InputWithPreviousOutput(input: inputToSign.input, previousOutput: inputToSign.previousOutput)
                },
                outputs: mutableTransaction.outputs,
                metaData: metadata
            ),
            descendantTransactions.map { $0.metaData.transactionHash.hs.reversedHex }
        )
    }
}

extension ReplacementTransactionBuilder {
    enum BuildError: Error {
        case invalidTransaction
        case noPreviousOutput
        case feeTooLow
        case rbfNotEnabled
        case unableToReplace
    }
}
