import Alamofire
import Foundation
import HsToolKit
import ObjectMapper

public class HsBlockHashFetcher: IBlockHashFetcher {
    private static let paginationLimit = 100

    private let hsUrl: String
    private let networkManager: NetworkManager

    public init(hsUrl: String, logger: Logger? = nil) {
        self.hsUrl = hsUrl
        networkManager = NetworkManager(logger: logger)
    }

    public func fetch(heights: [Int]) async throws -> [Int: String] {
        let parameters: Parameters = [
            "numbers": heights.map { String($0) }.joined(separator: ","),
        ]

        let blockResponses: [BlockResponse] = try await networkManager.fetch(url: "\(hsUrl)/hashes", method: .get, parameters: parameters)
        var hashes = [Int: String]()

        for response in blockResponses {
            hashes[response.height] = response.hash
        }

        return hashes
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
