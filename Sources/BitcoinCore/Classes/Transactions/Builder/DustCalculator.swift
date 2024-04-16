public class DustCalculator {
    private let minFeeRate: Int
    private let sizeCalculator: ITransactionSizeCalculator

    public init(dustRelayTxFee: Int, sizeCalculator: ITransactionSizeCalculator) {
        // https://github.com/bitcoin/bitcoin/blob/master/src/policy/feerate.cpp#L26
        minFeeRate = dustRelayTxFee / 1000

        self.sizeCalculator = sizeCalculator
    }
}

extension DustCalculator: IDustCalculator {
    public func dust(type: ScriptType, dustThreshold: Int?) -> Int {
        // https://github.com/bitcoin/bitcoin/blob/master/src/policy/policy.cpp#L14

        var size = sizeCalculator.outputSize(type: type)

        switch type {
        case .p2wpkh, .p2wsh:
            size += sizeCalculator.inputSize(type: .p2wpkh) + sizeCalculator.witnessSize(type: .p2wpkh) / 4
        case .p2tr:
            size += sizeCalculator.inputSize(type: .p2tr) + sizeCalculator.witnessSize(type: .p2tr) / 4
        default:
            size += sizeCalculator.inputSize(type: .p2pkh)
        }

        var dust = size * minFeeRate

        if let dustThreshold, dustThreshold > dust {
            dust = dustThreshold
        }

        return dust
    }
}
