import Alamofire
import HsToolKit
import ObjectMapper

public class BlockchainComApi {
    private static let paginationLimit = 100
    private static let addressesLimit = 50

    private let url: String
    private let delayedNetworkManager: NetworkManager
    private let networkManager: NetworkManager
    private let blockHashFetcher: IBlockHashFetcher

    public init(url: String, blockHashFetcher: IBlockHashFetcher, logger: Logger? = nil) {
        self.url = url
        self.blockHashFetcher = blockHashFetcher
        delayedNetworkManager = NetworkManager(interRequestInterval: 0.5, logger: logger)
        networkManager = NetworkManager(logger: logger)
    }

    private func addresses(addresses: [String], offset: Int = 0) async throws -> AddressesResponse {
        let parameters: Parameters = [
            "active": addresses.joined(separator: "|"),
            "n": Self.paginationLimit,
            "offset": offset,
        ]

        return try await delayedNetworkManager.fetch(url: "\(url)/multiaddr", method: .get, parameters: parameters)
    }

    private func _transactions(addressChunk: [String], stopHeight: Int?, offset: Int = 0) async throws -> [TransactionResponse] {
        let addressesResponse = try await addresses(addresses: addressChunk, offset: offset)
        let transactions = addressesResponse.transactions

        let filteredTransactions = transactions.filter { transaction in
            if let height = transaction.blockHeight, let stopHeight {
                return stopHeight < height
            } else {
                return true
            }
        }

        if filteredTransactions.count < Self.paginationLimit {
            return filteredTransactions
        }

        let nextTransactions = try await _transactions(addressChunk: addressChunk, stopHeight: stopHeight, offset: offset + Self.paginationLimit)

        return transactions + nextTransactions
    }

    private func _transactions(allAddresses: [String], stopHeight: Int?) async throws -> [TransactionResponse] {
        var transactions = [TransactionResponse]()

        for chunk in allAddresses.chunked(into: Self.addressesLimit) {
            let _transactions = try await _transactions(addressChunk: chunk, stopHeight: stopHeight)
            transactions.append(contentsOf: _transactions)
        }

        return transactions
    }
}

extension BlockchainComApi: IApiTransactionProvider {
    public func transactions(addresses: [String], stopHeight: Int?) async throws -> [ApiTransactionItem] {
        let transactions = try await _transactions(allAddresses: addresses, stopHeight: stopHeight)
        let blockHeights = Array(Set(transactions.compactMap(\.blockHeight)))

        guard !blockHeights.isEmpty else {
            return []
        }

        let hashesMap = try await blockHashFetcher.fetch(heights: blockHeights)

        let items = transactions.compactMap { response -> ApiTransactionItem? in
            guard let blockHeight = response.blockHeight, let blockHash = hashesMap[blockHeight] else {
                return nil
            }

            return ApiTransactionItem(
                blockHash: blockHash,
                blockHeight: blockHeight,
                apiAddressItems: response.outputs.map {
                    ApiAddressItem(script: $0.script, address: $0.address)
                }
            )
        }

        return items
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
}
