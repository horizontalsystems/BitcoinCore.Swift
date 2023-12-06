import BigInt
import Foundation

public class ProofOfWorkValidator: IBlockValidator {
    private let difficultyEncoder: IDifficultyEncoder

    public init(difficultyEncoder: IDifficultyEncoder) {
        self.difficultyEncoder = difficultyEncoder
    }

    public func validate(block: Block, previousBlock _: Block) throws {
        guard difficultyEncoder.compactFrom(hash: block.headerHash) < block.bits else {
            throw BitcoinCoreErrors.BlockValidation.invalidProofOfWork
        }
    }
}
