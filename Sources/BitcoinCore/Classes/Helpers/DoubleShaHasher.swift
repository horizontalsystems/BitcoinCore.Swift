import Foundation
import HsCryptoKit

public class DoubleShaHasher: IHasher {

    public init() {}

    public func hash(data: Data) -> Data {
        Crypto.doubleSha256(data)
    }

}
