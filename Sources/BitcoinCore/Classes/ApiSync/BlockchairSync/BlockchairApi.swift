import Alamofire
import Foundation
import HsToolKit
import ObjectMapper

public class BlockchairApi {
    private let baseUrl = "https://api.blockchair.com/"
    private let chainId: String
    private let limit = 100
    private let secretKey: String
    private let networkManager: NetworkManager

    public init(secretKey: String, chainId: String = "bitcoin", logger: Logger? = nil) {
        self.secretKey = secretKey
        self.chainId = chainId
        networkManager = NetworkManager(logger: logger)
    }

    private func _transactions(addresses: [String], stopHeight: Int? = nil, receivedScripts: [ApiAddressItem] = [], receivedTransactions: [BlockchairTransactionsReponse.Transaction] = []) async throws -> ([ApiAddressItem], [BlockchairTransactionsReponse.Transaction]) {
        let parameters: Parameters = [
            "transaction_details": true,
            "limit": "\(limit),0",
            "offset": "\(receivedTransactions.count),0",
            "key": secretKey
        ]
        let url = "\(baseUrl)\(chainId)/dashboards/addresses/\(addresses.joined(separator: ","))"

        do {
            let response: BlockchairTransactionsReponse = try await networkManager.fetch(url: url, method: .get, parameters: parameters)
            let scriptsSlice = response.data.addresses.map { ApiAddressItem(script: $0.value.script, address: $0.key) }
            let filteredTransactions = response.data.transactions.filter { transaction in
                if let height = transaction.blockId, let stopHeight = stopHeight {
                    return stopHeight < height
                } else {
                    return true
                }
            }
            let scriptsMerged = receivedScripts + scriptsSlice
            let transactionsMerged = receivedTransactions + filteredTransactions

            if filteredTransactions.count < limit {
                return (scriptsMerged, transactionsMerged)
            } else {
                return try await _transactions(addresses: addresses, stopHeight: stopHeight,
                                               receivedScripts: scriptsMerged, receivedTransactions: transactionsMerged)
            }
        } catch let responseError as HsToolKit.NetworkManager.ResponseError {
            if responseError.statusCode == 404 {
                return ([], [])
            } else {
                throw responseError
            }
        } catch {
            throw error
        }
    }

    private func _blockHashes(heights: [Int]) async throws -> [Int: String] {
        let parameters: Parameters = [
            "limit": "0",
            "key": secretKey
        ]
        let heightsStr = heights.map { "\($0)" }.joined(separator: ",")
        let url = "\(baseUrl)\(chainId)/dashboards/blocks/\(heightsStr)"

        do {
            let response: BlockchairBlocksResponse = try await networkManager.fetch(url: url, method: .get, parameters: parameters)
            var map = [Int: String]()
            for (key, value) in response.data {
                guard let height = Int(key) else {
                    continue
                }
                map[height] = value.block.hash
            }

            return map
        } catch let responseError as HsToolKit.NetworkManager.ResponseError {
            if responseError.statusCode == 404 {
                return [:]
            } else {
                throw responseError
            }
        } catch {
            throw error
        }
    }

    func transactions(addresses: [String], stopHeight: Int?) async throws -> [ApiTransactionItem] {
        var transactionItemsMap = [String: ApiTransactionItem]()

        for chunk in addresses.chunked(into: 100) {
            let (addressItems, transactions) = try await _transactions(addresses: chunk, stopHeight: stopHeight)

            for transaction in transactions {
                guard let blockHeight = transaction.blockId else {
                    continue
                }

                var transactionItem: ApiTransactionItem
                if let existingItem = transactionItemsMap[transaction.hash] {
                    transactionItem = existingItem
                } else {
                    transactionItem = ApiTransactionItem(
                        blockHash: "",
                        blockHeight: blockHeight,
                        apiAddressItems: []
                    )
                    transactionItemsMap[transaction.hash] = transactionItem
                }

                if let addressItem = addressItems.first(where: { transaction.address == $0.address }) {
                    transactionItem.apiAddressItems.append(addressItem)
                }
            }
        }

        return Array(transactionItemsMap.values)
    }

    func lastBlockHeader() async throws -> ApiBlockHeaderItem {
        let parameters: Parameters = [
            "limit": "0",
            "key": secretKey
        ]
        let url = "\(baseUrl)\(chainId)/stats"
        let response: BlockchairStatsReponse = try await networkManager.fetch(url: url, method: .get, parameters: parameters)

        return ApiBlockHeaderItem(hash: response.data.bestBlockHash.hs.reversedHexData!, height: response.data.bestBlockHeight, timestamp: response.data.bestBlockTime)
    }

    func blockHashes(heights: [Int]) async throws -> [Int: String] {
        var hashesMap = [Int: String]()

        for chunk in heights.chunked(into: 10) {
            let map = try await _blockHashes(heights: chunk)
            hashesMap.merge(map, uniquingKeysWith: { a, _ in a })
        }

        return hashesMap
    }
}
