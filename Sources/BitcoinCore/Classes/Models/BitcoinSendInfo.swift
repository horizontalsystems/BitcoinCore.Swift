import Foundation

public struct BitcoinSendInfo {
    public let fee: Int
    public let unspentOutputs: [UnspentOutput]
}
