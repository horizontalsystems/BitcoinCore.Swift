import Alamofire
import HsToolKit
import ObjectMapper

public class InsightApi {
    private static let paginationLimit = 50
    private static let addressesLimit = 99

    private let url: String
    private let networkManager: NetworkManager

    public init(url: String, logger: Logger? = nil) {
        self.url = url
        networkManager = NetworkManager(logger: logger)
    }
}

extension InsightApi: IApiTransactionProvider {
    public func transactions(addresses: [String], stopHeight: Int?) async throws -> [ApiTransactionItem] {
        let items: [InsightTransactionItem] = try await sendAddressesRecursive(addresses: addresses)

        return items.compactMap { item -> ApiTransactionItem? in
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

    private func sendAddressesRecursive(addresses: [String], from: Int = 0, transactions: [InsightTransactionItem] = []) async throws -> [InsightTransactionItem] {
        let last = min(from + InsightApi.addressesLimit, addresses.count)
        let chunk = addresses[from ..< last].joined(separator: ",")

        let result = try await getTransactionsRecursive(addresses: chunk)
        let resultTransactions = transactions + result

        if last >= addresses.count {
            return resultTransactions
        } else {
            return try await sendAddressesRecursive(addresses: addresses, from: from + InsightApi.addressesLimit, transactions: resultTransactions)
        }
    }

    private func getTransactionsRecursive(addresses: String, from: Int = 0, transactions: [InsightTransactionItem] = []) async throws -> [InsightTransactionItem] {
        let result = try await getTransactions(addresses: addresses, from: from)
        let resultTransactions = transactions + result.transactionItems.map { $0 as InsightTransactionItem }

        if result.totalItems <= result.to {
            return resultTransactions
        } else {
            return try await getTransactionsRecursive(addresses: addresses, from: result.to, transactions: resultTransactions)
        }
    }

    private func getTransactions(addresses: String, from: Int = 0) async throws -> InsightResponseItem {
        let parameters: Parameters = [
            "from": from,
            "to": from + InsightApi.paginationLimit
        ]
        let path = "/addrs/\(addresses)/txs"

        return try await networkManager.fetch(url: url + path, method: .get, parameters: parameters)
    }

    class InsightResponseItem: ImmutableMappable {
        public let totalItems: Int
        public let from: Int
        public let to: Int
        public let transactionItems: [InsightTransactionItem]

        public init(totalItems: Int, from: Int, to: Int, transactionItems: [InsightTransactionItem]) {
            self.totalItems = totalItems
            self.from = from
            self.to = to
            self.transactionItems = transactionItems
        }

        public required init(map: Map) throws {
            totalItems = try map.value("totalItems")
            var fromInt: Int?
            if let fromString: String = try? map.value("from") {
                fromInt = Int(fromString)
            } else {
                fromInt = try? map.value("from")
            }
            guard let from = fromInt else {
                throw MapError(key: "from", currentValue: "n/a", reason: "can't parse from value")
            }
            self.from = from
            to = try map.value("to")
            transactionItems = try map.value("items")
        }
    }

    class InsightTransactionItem: BCoinTransactionItem {
        required init(map: Map) throws {
            let blockHash: String? = try? map.value("blockhash")
            let blockHeight: Int? = try? map.value("blockheight")
            let txOutputs: [InsightTransactionOutputItem] = (try? map.value("vout")) ?? []
            super.init(hash: blockHash, height: blockHeight, txOutputs: txOutputs.map { $0 as BCoinTransactionOutputItem })
        }
    }

    class InsightTransactionOutputItem: BCoinTransactionOutputItem {
        required init(map: Map) throws {
            let script: String = (try? map.value("scriptPubKey.hex")) ?? ""
            let address: [String] = (try? map.value("scriptPubKey.addresses")) ?? []
            super.init(script: script, address: address.joined())
        }
    }
}
