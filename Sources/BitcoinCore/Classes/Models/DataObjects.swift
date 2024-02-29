import Foundation
import HsCryptoKit

public struct BlockHeader {
    public let version: Int
    public let headerHash: Data
    public let previousBlockHeaderHash: Data
    public let merkleRoot: Data
    public let timestamp: Int
    public let bits: Int
    public let nonce: Int

    public init(version: Int, headerHash: Data, previousBlockHeaderHash: Data, merkleRoot: Data, timestamp: Int, bits: Int, nonce: Int) {
        self.version = version
        self.headerHash = headerHash
        self.previousBlockHeaderHash = previousBlockHeaderHash
        self.merkleRoot = merkleRoot
        self.timestamp = timestamp
        self.bits = bits
        self.nonce = nonce
    }
}

open class FullTransaction {
    public let header: Transaction
    public let inputs: [Input]
    public let outputs: [Output]
    public let metaData = TransactionMetadata()

    public init(header: Transaction, inputs: [Input], outputs: [Output], forceHashUpdate: Bool = true) {
        self.header = header
        self.inputs = inputs
        self.outputs = outputs

        if forceHashUpdate {
            let hash = Crypto.doubleSha256(TransactionSerializer.serialize(transaction: self, withoutWitness: true))
            set(hash: hash)
        }
    }

    public func set(hash: Data) {
        header.dataHash = hash
        metaData.transactionHash = hash

        for input in inputs {
            input.transactionHash = header.dataHash
        }
        for output in outputs {
            output.transactionHash = header.dataHash
        }
    }
}

public struct InputToSign {
    let input: Input
    let previousOutput: Output
    let previousOutputPublicKey: PublicKey
}

public struct OutputWithPublicKey {
    let output: Output
    let publicKey: PublicKey
    let spendingInput: Input?
    let spendingBlockHeight: Int?
}

public struct InputWithPreviousOutput {
    let input: Input
    let previousOutput: Output?
}

public struct TransactionWithBlock {
    public let transaction: Transaction
    let blockHeight: Int?
}

public struct UnspentOutput {
    public let output: Output
    public let publicKey: PublicKey
    public let transaction: Transaction
    public let blockHeight: Int?

    public init(output: Output, publicKey: PublicKey, transaction: Transaction, blockHeight: Int? = nil) {
        self.output = output
        self.publicKey = publicKey
        self.transaction = transaction
        self.blockHeight = blockHeight
    }

    public var info: UnspentOutputInfo {
        .init(
            outputIndex: output.index,
            transactionHash: output.transactionHash,
            timestamp: TimeInterval(transaction.timestamp),
            address: output.address,
            value: output.value
        )
    }
}

public struct UnspentOutputInfo: Hashable, Equatable {
    public var outputIndex: Int
    public var transactionHash: Data
    public let timestamp: TimeInterval
    public let address: String?
    public let value: Int

    public static func ==(lhs: UnspentOutputInfo, rhs: UnspentOutputInfo) -> Bool {
        lhs.outputIndex == rhs.outputIndex &&
        lhs.transactionHash == rhs.transactionHash
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(outputIndex)
        hasher.combine(transactionHash)
    }
}

public extension Array where Element == UnspentOutputInfo {
    func outputs(from outputs: [UnspentOutput]) -> [UnspentOutput] {
        let selectedKeys = map { ($0.outputIndex, $0.transactionHash) }
        return outputs.filter { output in
            selectedKeys.contains { i, hash in
                i == output.output.index && hash == output.output.transactionHash
            }
        }
    }
}

public struct FullTransactionForInfo {
    public let transactionWithBlock: TransactionWithBlock
    let inputsWithPreviousOutputs: [InputWithPreviousOutput]
    let outputs: [Output]
    let metaData: TransactionMetadata

    var rawTransaction: String {
        let fullTransaction = FullTransaction(
            header: transactionWithBlock.transaction,
            inputs: inputsWithPreviousOutputs.map(\.input),
            outputs: outputs
        )

        return TransactionSerializer.serialize(transaction: fullTransaction).hs.hex
    }
}

public struct PublicKeyWithUsedState {
    let publicKey: PublicKey
    let used: Bool
}
