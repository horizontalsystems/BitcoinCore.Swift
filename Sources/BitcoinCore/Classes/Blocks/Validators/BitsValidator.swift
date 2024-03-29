import Foundation

public class BitsValidator: IBlockChainedValidator {
    public init() {}

    public func validate(block: Block, previousBlock: Block) throws {
        guard block.bits == previousBlock.bits else {
            throw BitcoinCoreErrors.BlockValidation.notEqualBits
        }
    }

    public func isBlockValidatable(block _: Block, previousBlock _: Block) -> Bool {
        true
    }
}
