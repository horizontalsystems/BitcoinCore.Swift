import Foundation

class TransactionSigner {
    enum SignError: Error {
        case notSupportedScriptType
        case noRedeemScript
    }

    private let ecdsaInputSigner: IInputSigner
    private let schnorrInputSigner: IInputSigner

    init(ecdsaInputSigner: IInputSigner, schnorrInputSigner: IInputSigner) {
        self.ecdsaInputSigner = ecdsaInputSigner
        self.schnorrInputSigner = schnorrInputSigner
    }

    private func signatureScript(from sigScriptData: [Data]) -> Data {
        sigScriptData.reduce(Data()) {
            $0 + OpCode.push($1)
        }
    }

    private func ecdsaSign(index: Int, mutableTransaction: MutableTransaction) throws {
        let inputToSign = mutableTransaction.inputsToSign[index]
        let previousOutput = inputToSign.previousOutput
        let publicKey = inputToSign.previousOutputPublicKey
        var sigScriptData = try ecdsaInputSigner.sigScriptData(
            transaction: mutableTransaction.transaction,
            inputsToSign: mutableTransaction.inputsToSign,
            outputs: mutableTransaction.outputs,
            index: index
        )

        switch previousOutput.scriptType {
        case .p2pkh:
            inputToSign.input.signatureScript = signatureScript(from: sigScriptData)
        case .p2wpkh:
            mutableTransaction.transaction.segWit = true
            inputToSign.input.witnessData = sigScriptData
        case .p2wpkhSh:
            mutableTransaction.transaction.segWit = true
            inputToSign.input.witnessData = sigScriptData
            inputToSign.input.signatureScript = OpCode.push(OpCode.segWitOutputScript(publicKey.hashP2pkh, versionByte: 0))
        case .p2sh:
            guard let redeemScript = previousOutput.redeemScript else {
                throw SignError.noRedeemScript
            }

            if let signatureScriptFunction = previousOutput.signatureScriptFunction {
                // non-standard P2SH signature script
                inputToSign.input.signatureScript = signatureScriptFunction(sigScriptData)
            } else {
                // standard (signature, publicKey, redeemScript) signature script
                sigScriptData.append(redeemScript)
                inputToSign.input.signatureScript = signatureScript(from: sigScriptData)
            }
        default: throw SignError.notSupportedScriptType
        }
    }

    private func schnorrSign(index: Int, mutableTransaction: MutableTransaction) throws {
        let inputToSign = mutableTransaction.inputsToSign[index]
        let previousOutput = inputToSign.previousOutput

        guard previousOutput.scriptType == .p2tr else {
            throw SignError.notSupportedScriptType
        }

        let witnessData = try schnorrInputSigner.sigScriptData(
            transaction: mutableTransaction.transaction,
            inputsToSign: mutableTransaction.inputsToSign,
            outputs: mutableTransaction.outputs,
            index: index
        )

        mutableTransaction.transaction.segWit = true
        inputToSign.input.witnessData = witnessData
    }
}

extension TransactionSigner: ITransactionSigner {
    func sign(mutableTransaction: MutableTransaction) throws {
        for (index, inputToSign) in mutableTransaction.inputsToSign.enumerated() {
            if inputToSign.previousOutput.scriptType == .p2tr {
                try schnorrSign(index: index, mutableTransaction: mutableTransaction)
            } else {
                try ecdsaSign(index: index, mutableTransaction: mutableTransaction)
            }
        }
    }
}
