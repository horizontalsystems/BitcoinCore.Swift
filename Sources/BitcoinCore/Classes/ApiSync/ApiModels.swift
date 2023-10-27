import Foundation
import ObjectMapper

public struct ApiTransactionItem {
    public let blockHash: String
    public let blockHeight: Int
    public var apiAddressItems: [ApiAddressItem]

    public init(blockHash: String, blockHeight: Int, apiAddressItems: [ApiAddressItem]) {
        self.blockHash = blockHash
        self.blockHeight = blockHeight
        self.apiAddressItems = apiAddressItems
    }
}

public struct ApiAddressItem {
    public let script: String
    public let address: String?

    public init(script: String, address: String?) {
        self.script = script
        self.address = address
    }
}

public struct ApiBlockHeaderItem {
    let hash: Data
    let height: Int
    let timestamp: Int
}
