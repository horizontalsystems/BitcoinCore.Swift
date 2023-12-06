import Foundation
import HsExtensions

public extension String {
    var reversedData: Data? {
        hs.hexData.map { Data($0.reversed()) }
    }
}
