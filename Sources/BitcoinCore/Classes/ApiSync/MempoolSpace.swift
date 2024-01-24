import Alamofire
import HsToolKit
import ObjectMapper

public class MempoolSpaceApi {
    private let url: String
    private let networkManager: NetworkManager

    public init(url: String, logger: Logger? = nil) {
        self.url = url
        networkManager = NetworkManager(logger: logger)
    }
}

extension MempoolSpaceApi: IApiTransactionProvider {
    
    
    public func transactions(addresses: [String], stopHeight _: Int?) async throws -> [ApiTransactionItem] {
        
        var bcoinItems : [MempoolSpaceTransactionItem] = []
        
        await withTaskGroup(of: [MempoolSpaceTransactionItem].self) { group in
            for addr in addresses {
                group.addTask {
                    let path = "/address/\(addr)/txs"
                    
                    let bcoinItems: [MempoolSpaceTransactionItem]? = try? await  self.networkManager.fetch(url: self.url + path, method: .get)
                    return bcoinItems ?? []
                }
            }
            for await result in group {
                bcoinItems.append(contentsOf: result)
            }
        }
            
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

open class MempoolSpaceTransactionItem: ImmutableMappable {
    public let blockHash: String?
    public let blockHeight: Int?
    public let txOutputs: [MempoolSpaceTransactionOutputItem]

    public init(hash: String?, height: Int?, txOutputs: [MempoolSpaceTransactionOutputItem]) {
        blockHash = hash
        blockHeight = height
        self.txOutputs = txOutputs
    }

    public required init(map: Map) throws {
        blockHash = try? map.value("status.block_hash")
        blockHeight = try? map.value("status.block_height")
        txOutputs = (try? map.value("vout")) ?? []
    }

    static func == (lhs: MempoolSpaceTransactionItem, rhs: MempoolSpaceTransactionItem) -> Bool {
        lhs.blockHash == rhs.blockHash && lhs.blockHeight == rhs.blockHeight
    }
}

open class MempoolSpaceTransactionOutputItem: ImmutableMappable {
    public let script: String
    public let address: String?

    public init(script: String, address: String?) {
        self.script = script
        self.address = address
    }

    public required init(map: Map) throws {
        script = try map.value("scriptpubkey")
        address = try map.value("scriptpubkey_address")
    }
}
