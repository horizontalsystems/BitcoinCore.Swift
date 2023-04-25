import ObjectMapper
import Alamofire
import HsToolKit

public class BCoinApi {
    private let url: String
    private let networkManager: NetworkManager

    public init(url: String, logger: Logger? = nil) {
        self.url = url
        networkManager = NetworkManager(logger: logger)
    }

}

extension BCoinApi: ISyncTransactionApi {

    public func transactions(addresses: [String]) async throws -> [SyncTransactionItem] {
        let parameters: Parameters = [
            "addresses": addresses
        ]
        let path = "/tx/address"

        return try await networkManager.fetch(url: url + path, method: .post, parameters: parameters, encoding: JSONEncoding.default)
    }

}
