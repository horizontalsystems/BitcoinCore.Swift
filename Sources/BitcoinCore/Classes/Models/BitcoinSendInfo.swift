import Foundation

public struct BitcoinSendInfo {
    public let unspentOutputs: [UnspentOutput]
    public let fee: Int
    public let changeValue: Int?
    public let changeAddress: Address?
}
