import Alamofire
import HsToolKit
import ObjectMapper

public class BCoinApi {
    private let url: String
    private let networkManager: NetworkManager

    public init(url: String, logger: Logger? = nil) {
        self.url = url
        networkManager = NetworkManager(logger: logger)
    }
}

extension BCoinApi: IApiTransactionProvider {
    public func transactions(addresses: [String], stopHeight _: Int?) async throws -> [ApiTransactionItem] {
        let parameters: Parameters = [
            "addresses": addresses,
        ]
        let path = "/tx/address"

        let bcoinItems: [BCoinTransactionItem] = try await networkManager.fetch(url: url + path, method: .post, parameters: parameters, encoding: JSONEncoding.default)
        return bcoinItems.compactMap { item -> ApiTransactionItem? in
            guard let blockHash = item.blockHash, let blockHeight = item.blockHeight else {
                return nil
            }

            return ApiTransactionItem(
                blockHash: blockHash, blockHeight: blockHeight,
                apiAddressItems: item.txOutputs.map { outputItem in
                    ApiAddressItem(script: outputItem.script, address: outputItem.address)
                }
            )
        }
    }
}

open class BCoinTransactionItem: ImmutableMappable {
    public let blockHash: String?
    public let blockHeight: Int?
    public let txOutputs: [BCoinTransactionOutputItem]

    public init(hash: String?, height: Int?, txOutputs: [BCoinTransactionOutputItem]) {
        blockHash = hash
        blockHeight = height
        self.txOutputs = txOutputs
    }

    public required init(map: Map) throws {
        blockHash = try? map.value("block")
        blockHeight = try? map.value("height")
        txOutputs = (try? map.value("outputs")) ?? []
    }

    static func == (lhs: BCoinTransactionItem, rhs: BCoinTransactionItem) -> Bool {
        lhs.blockHash == rhs.blockHash && lhs.blockHeight == rhs.blockHeight
    }
}

open class BCoinTransactionOutputItem: ImmutableMappable {
    public let script: String
    public let address: String?

    public init(script: String, address: String?) {
        self.script = script
        self.address = address
    }

    public required init(map: Map) throws {
        script = try map.value("script")
        address = try map.value("address")
    }
}
