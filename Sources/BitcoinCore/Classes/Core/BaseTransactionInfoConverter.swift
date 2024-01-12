import Foundation
import HsExtensions

public protocol IBaseTransactionInfoConverter {
    func transactionInfo<T: TransactionInfo>(fromTransaction transactionForInfo: FullTransactionForInfo) -> T
}

public class BaseTransactionInfoConverter: IBaseTransactionInfoConverter {
    private let pluginManager: IPluginManager

    public init(pluginManager: IPluginManager) {
        self.pluginManager = pluginManager
    }

    public func transactionInfo<T: TransactionInfo>(fromTransaction transactionForInfo: FullTransactionForInfo) -> T {
        if let invalidTransactionInfo: T = transactionInfo(fromInvalidTransaction: transactionForInfo) {
            return invalidTransactionInfo
        }

        var inputsInfo = [TransactionInputInfo]()
        var outputsInfo = [TransactionOutputInfo]()
        let transaction = transactionForInfo.transactionWithBlock.transaction
        let transactionTimestamp = transaction.timestamp

        for inputWithPreviousOutput in transactionForInfo.inputsWithPreviousOutputs {
            var mine = false
            var value: Int? = nil

            if let previousOutput = inputWithPreviousOutput.previousOutput {
                value = previousOutput.value

                if previousOutput.publicKeyPath != nil {
                    mine = true
                }
            }

            inputsInfo.append(TransactionInputInfo(mine: mine, address: inputWithPreviousOutput.input.address, value: value))
        }

        for output in transactionForInfo.outputs {
            let outputInfo = TransactionOutputInfo(mine: output.publicKeyPath != nil, changeOutput: output.changeOutput, value: output.value, address: output.address)

            if let pluginId = output.pluginId, let pluginDataString = output.pluginData {
                outputInfo.pluginId = pluginId
                outputInfo.pluginDataString = pluginDataString
                outputInfo.pluginData = pluginManager.parsePluginData(fromPlugin: pluginId, pluginDataString: pluginDataString, transactionTimestamp: transactionTimestamp)
            } else if output.scriptType == .nullData, let payload = output.lockingScriptPayload, !payload.isEmpty {
                // read first byte to get data length and parse first message
                let byteStream = ByteStream(payload)
                let _ = byteStream.read(UInt8.self) // read op_return
                let length = byteStream.read(VarInt.self).underlyingValue
                if byteStream.availableBytes >= length {
                    let data = byteStream.read(Data.self, count: Int(length))
                    outputInfo.memo = String(data: data, encoding: .utf8)   //todo: make memo manager if need parse not only memo (some instructions)
                }
            }

            outputsInfo.append(outputInfo)
        }

        return T(
            uid: transaction.uid,
            transactionHash: transaction.dataHash.hs.reversedHex,
            transactionIndex: transaction.order,
            inputs: inputsInfo,
            outputs: outputsInfo,
            amount: transactionForInfo.metaData.amount,
            type: transactionForInfo.metaData.type,
            fee: transactionForInfo.metaData.fee,
            blockHeight: transactionForInfo.transactionWithBlock.blockHeight,
            timestamp: transactionTimestamp,
            status: transaction.status,
            conflictingHash: transaction.conflictingTxHash?.hs.reversedHex
        )
    }

    private func transactionInfo<T: TransactionInfo>(fromInvalidTransaction transactionForInfo: FullTransactionForInfo) -> T? {
        guard let invalidTransaction = transactionForInfo.transactionWithBlock.transaction as? InvalidTransaction else {
            return nil
        }

        guard let transactionInfo: T = try? JSONDecoder().decode(T.self, from: invalidTransaction.transactionInfoJson) else {
            return nil
        }

        for addressInfo in transactionInfo.outputs {
            if let pluginId = addressInfo.pluginId, let pluginDataString = addressInfo.pluginDataString {
                addressInfo.pluginData = pluginManager.parsePluginData(fromPlugin: pluginId, pluginDataString: pluginDataString, transactionTimestamp: invalidTransaction.timestamp)
            }
        }

        return transactionInfo
    }
}
