import Foundation

class ReplacementTransactionBuilder {
    private let storage: IStorage
    private let sizeCalculator: ITransactionSizeCalculator
    private let dustCalculator: IDustCalculator
    private let factory: IFactory
    private let metadataExtractor: TransactionMetadataExtractor
    private let pluginManager: IPluginManager
    private let unspentOutputProvider: IUnspentOutputProvider
    private let conflictsResolver: TransactionConflictsResolver

    init(storage: IStorage, sizeCalculator: ITransactionSizeCalculator, dustCalculator: IDustCalculator, factory: IFactory,
         metadataExtractor: TransactionMetadataExtractor, pluginManager: IPluginManager, unspentOutputProvider: IUnspentOutputProvider,
         transactionConflictsResolver: TransactionConflictsResolver)
    {
        self.storage = storage
        self.sizeCalculator = sizeCalculator
        self.dustCalculator = dustCalculator
        self.factory = factory
        self.metadataExtractor = metadataExtractor
        self.pluginManager = pluginManager
        self.unspentOutputProvider = unspentOutputProvider
        conflictsResolver = transactionConflictsResolver
    }

    private func replacementTransaction(minFee: Int, minFeeRate: Int, utxo: [Output], fixedOutputs: [Output], outputs: [Output]) throws -> (outputs: [Output], fee: Int)? {
        var minFee = minFee
        var outputs = outputs

        let size = try sizeCalculator.transactionSize(
            previousOutputs: utxo,
            outputs: fixedOutputs + outputs
        )

        let inputsValue = utxo.map(\.value).reduce(0, +)
        let outputsValue = (fixedOutputs + outputs).map(\.value).reduce(0, +)
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
            throw ReplacementTransactionBuildError.invalidTransaction
        }

        return UnspentOutput(output: previousOutput, publicKey: publicKey, transaction: transaction)
    }

    private func incrementedSequence(of inputWithPreviousOutput: InputWithPreviousOutput) -> Int {
        let input = inputWithPreviousOutput.input

        if inputWithPreviousOutput.previousOutput?.pluginId != nil {
            return pluginManager.incrementedSequence(of: inputWithPreviousOutput)
        }

        return min(input.sequence + 1, 0xFFFFFFFF)
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
                sequence: incrementedSequence(of: inputWithPreviousOutput)
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
        var fixedOutputs = originalFullInfo.outputs.filter { $0.publicKeyPath == nil || $0.pluginId != nil }
        let myOutputs = originalFullInfo.outputs.filter { $0.publicKeyPath != nil && $0.pluginId == nil }
        let myChangeOutputs = myOutputs.filter { $0.changeOutput }.sorted { a, b in a.value < b.value }
        let myExternalOutputs = myOutputs.filter { !$0.changeOutput }.sorted { a, b in a.value < b.value }

        var sortedOutputs = myChangeOutputs + myExternalOutputs
        if fixedOutputs.isEmpty, !sortedOutputs.isEmpty {
            fixedOutputs.append(sortedOutputs.removeLast())
        }

        let unusedUtxo = unspentOutputProvider.confirmedSpendableUtxo.sorted(by: { a, b in a.output.value < b.output.value })
        var optimalReplacement: (inputs: [UnspentOutput], outputs: [Output], fee: Int)?

        var utxoCount = 0
        repeat {
            var outputsCount = sortedOutputs.count
            repeat {
                let utxo = Array(unusedUtxo.prefix(utxoCount))
                let outputs = Array(sortedOutputs.suffix(outputsCount))

                if let replacement = try replacementTransaction(
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

                outputsCount -= 1
            } while outputsCount >= 0

            utxoCount += 1
        } while utxoCount <= unusedUtxo.count

        guard let optimalReplacement else {
            return nil
        }

        let mutableTransaction = MutableTransaction(outgoing: true)

        try setInputs(to: mutableTransaction, originalInputs: originalFullInfo.inputsWithPreviousOutputs, additionalInputs: optimalReplacement.inputs)
        setOutputs(to: mutableTransaction, outputs: fixedOutputs + optimalReplacement.outputs)

        return mutableTransaction
    }

    private func cancelReplacement(originalFullInfo: FullTransactionForInfo, minFee: Int, originalFeeRate: Int, fixedUtxo: [Output], userAddress: Address, publicKey: PublicKey) throws -> MutableTransaction? {
        let unusedUtxo = unspentOutputProvider.confirmedSpendableUtxo.sorted(by: { a, b in a.output.value < b.output.value })
        let originalInputsValue = fixedUtxo.map(\.value).reduce(0, +)
        var optimalReplacement: (inputs: [UnspentOutput], outputs: [Output], fee: Int)?

        var utxoCount = 0
        repeat {
            guard originalInputsValue - minFee >= dustCalculator.dust(type: userAddress.scriptType) else {
                utxoCount += 1
                continue
            }

            let utxo = Array(unusedUtxo.prefix(utxoCount))
            let outputs = [factory.output(withIndex: 0, address: userAddress, value: originalInputsValue - minFee, publicKey: publicKey)]

            if let replacement = try replacementTransaction(
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

            utxoCount += 1
        } while utxoCount <= unusedUtxo.count

        guard let optimalReplacement else {
            return nil
        }

        let mutableTransaction = MutableTransaction(outgoing: true)

        try setInputs(to: mutableTransaction, originalInputs: originalFullInfo.inputsWithPreviousOutputs, additionalInputs: optimalReplacement.inputs)
        setOutputs(to: mutableTransaction, outputs: optimalReplacement.outputs)

        return mutableTransaction
    }

    func replacementTransaction(transactionHash: String, minFee: Int, type: ReplacementType) throws -> (MutableTransaction, FullTransactionForInfo, [String]) {
        guard let transactionHash = transactionHash.hs.reversedHexData,
              let originalFullInfo = storage.transactionFullInfo(byHash: transactionHash),
              originalFullInfo.transactionWithBlock.blockHeight == nil,
              let originalFee = originalFullInfo.metaData.fee,
              originalFullInfo.metaData.type != .incoming
        else {
            throw ReplacementTransactionBuildError.invalidTransaction
        }

        let fixedUtxo = originalFullInfo.inputsWithPreviousOutputs.compactMap { $0.previousOutput }
        guard fixedUtxo.count == originalFullInfo.inputsWithPreviousOutputs.count else {
            throw ReplacementTransactionBuildError.noPreviousOutput
        }

        guard originalFullInfo.inputsWithPreviousOutputs.contains(where: { $0.input.rbfEnabled }) else {
            throw ReplacementTransactionBuildError.rbfNotEnabled
        }

        let originalSize = try sizeCalculator.transactionSize(
            previousOutputs: fixedUtxo,
            outputs: originalFullInfo.outputs
        )

        let originalFeeRate = Int(originalFee / originalSize)
        let descendantTransactions = storage.descendantTransactionsFullInfo(of: transactionHash)
        let absoluteFee = descendantTransactions.map { $0.metaData.fee ?? 0 }.reduce(0, +)

        guard descendantTransactions.allSatisfy({ $0.transactionWithBlock.transaction.conflictingTxHash == nil }),
              !conflictsResolver.isTransactionReplaced(transaction: originalFullInfo.fullTransaction)
        else {
            throw ReplacementTransactionBuildError.alreadyReplaced
        }

        guard absoluteFee <= minFee else {
            throw ReplacementTransactionBuildError.feeTooLow
        }

        var mutableTransaction: MutableTransaction?
        switch type {
            case .speedUp:
                mutableTransaction = try speedUpReplacement(originalFullInfo: originalFullInfo, minFee: minFee, originalFeeRate: originalFeeRate, fixedUtxo: fixedUtxo)
            case .cancel(let userAddress, let publicKey):
                mutableTransaction = try cancelReplacement(originalFullInfo: originalFullInfo, minFee: minFee, originalFeeRate: originalFeeRate, fixedUtxo: fixedUtxo, userAddress: userAddress, publicKey: publicKey)
        }

        guard let mutableTransaction else {
            throw ReplacementTransactionBuildError.unableToReplace
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

    func replacementInfo(transactionHash: String, type: ReplacementType) -> (originalTransactionSize: Int, feeRange: Range<Int>)? {
        guard let transactionHash = transactionHash.hs.reversedHexData,
              let originalFullInfo = storage.transactionFullInfo(byHash: transactionHash),
              originalFullInfo.transactionWithBlock.blockHeight == nil,
              originalFullInfo.metaData.type != .incoming,
              let originalFee = originalFullInfo.metaData.fee
        else {
            return nil
        }

        let fixedUtxo = originalFullInfo.inputsWithPreviousOutputs.compactMap { $0.previousOutput }
        guard fixedUtxo.count == originalFullInfo.inputsWithPreviousOutputs.count else {
            return nil
        }

        let descendantTransactions = storage.descendantTransactionsFullInfo(of: transactionHash)
        let absoluteFee = descendantTransactions.map { $0.metaData.fee ?? 0 }.reduce(0, +)

        guard descendantTransactions.allSatisfy({ $0.transactionWithBlock.transaction.conflictingTxHash == nil }),
              !conflictsResolver.isTransactionReplaced(transaction: originalFullInfo.fullTransaction)
        else {
            return nil
        }

        let originalSize: Int
        let removableOutputsValue: Int

        switch type {
            case .speedUp:
                var fixedOutputs = originalFullInfo.outputs.filter { $0.publicKeyPath == nil || $0.pluginId != nil }
                let myOutputs = originalFullInfo.outputs.filter { $0.publicKeyPath != nil && $0.pluginId == nil }
                let myChangeOutputs = myOutputs.filter { $0.changeOutput }.sorted { a, b in a.value < b.value }
                let myExternalOutputs = myOutputs.filter { !$0.changeOutput }.sorted { a, b in a.value < b.value }

                var sortedOutputs = myChangeOutputs + myExternalOutputs
                if fixedOutputs.isEmpty, !sortedOutputs.isEmpty {
                    fixedOutputs.append(sortedOutputs.removeLast())
                }

                originalSize = (try? sizeCalculator.transactionSize(previousOutputs: fixedUtxo, outputs: fixedOutputs)) ?? 0
                removableOutputsValue = sortedOutputs.map(\.value).reduce(0, +)
            case .cancel(let userAddress, _):
                let dustValue = dustCalculator.dust(type: userAddress.scriptType)
                let fixedOutputs = [factory.output(withIndex: 0, address: userAddress, value: dustValue, publicKey: nil)]
                originalSize = (try? sizeCalculator.transactionSize(previousOutputs: fixedUtxo, outputs: fixedOutputs)) ?? 0
                removableOutputsValue = originalFullInfo.outputs.map(\.value).reduce(0, +) - dustValue
        }

        let confirmedUtxoTotalValue = unspentOutputProvider.confirmedSpendableUtxo.map(\.output.value).reduce(0, +)

        return (
            originalTransactionSize: originalSize,
            feeRange: absoluteFee ..< originalFee + removableOutputsValue + confirmedUtxoTotalValue
        )
    }
}

public enum ReplacementTransactionBuildError: Error {
    case invalidTransaction
    case noPreviousOutput
    case feeTooLow
    case rbfNotEnabled
    case unableToReplace
    case alreadyReplaced
}
