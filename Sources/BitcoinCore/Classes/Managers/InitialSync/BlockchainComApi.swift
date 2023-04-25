import ObjectMapper
import Alamofire
import HsToolKit

public class BlockchainComApi {
    private static let paginationLimit = 100
    private static let addressesLimit = 50

    private let url: String
    private let hsUrl: String
    private let delayedNetworkManager: NetworkManager
    private let networkManager: NetworkManager

    public init(url: String, hsUrl: String, logger: Logger? = nil) {
        self.url = url
        self.hsUrl = hsUrl
        delayedNetworkManager = NetworkManager(interRequestInterval: 0.5, logger: logger)
        networkManager = NetworkManager(logger: logger)
    }

    private func addresses(addresses: [String], offset: Int = 0) async throws -> AddressesResponse {
        let parameters: Parameters = [
            "active": addresses.joined(separator: "|"),
            "n": Self.paginationLimit,
            "offset": offset
        ]

        return try await delayedNetworkManager.fetch(url: "\(url)/multiaddr", method: .get, parameters: parameters)
    }

    private func blocks(heights: [Int]) async throws -> [BlockResponse] {
        let parameters: Parameters = [
            "numbers": heights.map { String($0) }.joined(separator: ",")
        ]

        return try await networkManager.fetch(url: "\(hsUrl)/hashes", method: .get, parameters: parameters)
    }

    private func items(transactionResponses: [TransactionResponse]) async throws -> [SyncTransactionItem] {
        let blockHeights = Array(Set(transactionResponses.compactMap { $0.blockHeight }))

        guard !blockHeights.isEmpty else {
            return []
        }

        let blocks = try await blocks(heights: blockHeights)

        return transactionResponses.compactMap { response in
            guard let block = blocks.first(where: { $0.height == response.blockHeight }) else {
                return nil
            }

            return SyncTransactionItem(
                    hash: block.hash,
                    height: block.height,
                    txOutputs: response.outputs.map {
                        SyncTransactionOutputItem(script: $0.script, address: $0.address)
                    }
            )
        }
    }

    private func items(addresses: [String], offset: Int) async throws -> [SyncTransactionItem] {
        let response = try await self.addresses(addresses: addresses, offset: offset)
        return try await items(transactionResponses: response.transactions)
    }

    private func items(addressChunk: [String], offset: Int = 0) async throws -> [SyncTransactionItem] {
        let chunkItems = try await items(addresses: addressChunk, offset: offset)

        if chunkItems.count < Self.paginationLimit {
            return chunkItems
        }

        let items = try await items(addressChunk: addressChunk, offset: offset + Self.paginationLimit)

        return chunkItems + items
    }

    public func items(allAddresses: [String], index: Int = 0) async throws -> [SyncTransactionItem] {
        let startIndex = index * Self.addressesLimit

        guard startIndex <= allAddresses.count else {
            return []
        }

        let endIndex = min(allAddresses.count, (index + 1) * Self.addressesLimit)
        let chunk = Array(allAddresses[startIndex..<endIndex])

        let items = try await items(addressChunk: chunk)
        let allItems = try await self.items(allAddresses: allAddresses, index: index + 1)

        return allItems + items
    }

}

extension BlockchainComApi: ISyncTransactionApi {

    public func transactions(addresses: [String]) async throws -> [SyncTransactionItem] {
        try await items(allAddresses: addresses)
    }

}

extension BlockchainComApi {

    struct AddressesResponse: ImmutableMappable {
        let transactions: [TransactionResponse]

        init(map: Map) throws {
            transactions = try map.value("txs")
        }
    }

    struct TransactionResponse: ImmutableMappable {
        let blockHeight: Int?
        let outputs: [TransactionOutputResponse]

        init(map: Map) throws {
            blockHeight = try? map.value("block_height")
            outputs = try map.value("out")
        }
    }

    struct TransactionOutputResponse: ImmutableMappable {
        let script: String
        let address: String?

        init(map: Map) throws {
            script = try map.value("script")
            address = try? map.value("addr")
        }
    }

    struct BlockResponse: ImmutableMappable {
        let height: Int
        let hash: String

        init(map: Map) throws {
            height = try map.value("number")
            hash = try map.value("hash")
        }
    }

}
