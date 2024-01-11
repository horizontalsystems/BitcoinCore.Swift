import Foundation
import ObjectMapper

enum BlockchairResponse {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    public static let dateStringToTimestampTransform: TransformOf<Int, String> = TransformOf(fromJSON: { string -> Int? in
        guard let string else {
            return nil
        }
        return dateFormatter.date(from: string).flatMap { Int($0.timeIntervalSince1970) }
    }, toJSON: { (value: Int?) in
        guard let value else {
            return nil
        }
        return dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(value)))
    })
}

struct BlockchairTransactionsReponse: ImmutableMappable {
    let data: ResponseData
    let context: ResponseContext

    init(map: Map) throws {
        data = try map.value("data")
        context = try map.value("context")
    }

    struct ResponseData: ImmutableMappable {
        let addresses: [String: Address]
        let transactions: [Transaction]

        init(map: Map) throws {
            addresses = try map.value("addresses")
            transactions = try map.value("transactions")
        }
    }

    struct ResponseContext: ImmutableMappable {
        let code: Int
        let limit: String
        let offset: String
        let results: Int
        let state: Int

        init(map: Map) throws {
            code = try map.value("code")
            limit = try map.value("limit")
            offset = try map.value("offset")
            results = try map.value("results")
            state = try map.value("state")
        }
    }

    struct Transaction: ImmutableMappable, Hashable {
        let blockId: Int?
        let hash: String
        let balanceChange: Int
        let address: String

        init(map: Map) throws {
            blockId = try map.value("block_id")
            hash = try map.value("hash")
            balanceChange = try map.value("balance_change")
            address = try map.value("address")
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(hash)
        }
    }

    struct Address: ImmutableMappable {
        let script: String

        init(map: Map) throws {
            script = try map.value("script_hex")
        }
    }
}

struct BlockchairStatsReponse: ImmutableMappable {
    let data: ResponseData

    init(map: Map) throws {
        data = try map.value("data")
    }

    struct ResponseData: ImmutableMappable {
        let bestBlockHeight: Int
        let bestBlockHash: String
        let bestBlockTime: Int

        init(map: Map) throws {
            bestBlockHeight = try map.value("best_block_height")
            bestBlockHash = try map.value("best_block_hash")
            bestBlockTime = try map.value("best_block_time", using: BlockchairResponse.dateStringToTimestampTransform)
        }
    }
}

struct BlockchairBlocksResponse: ImmutableMappable {
    let data: [String: BlockResponseMap]

    init(map: Map) throws {
        data = try map.value("data")
    }

    struct BlockResponseMap: ImmutableMappable {
        let block: BlockResponse

        init(map: Map) throws {
            block = try map.value("block")
        }
    }

    struct BlockResponse: ImmutableMappable {
        let hash: String

        init(map: Map) throws {
            hash = try map.value("hash")
        }
    }
}
