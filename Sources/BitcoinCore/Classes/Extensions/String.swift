import Foundation
import HsExtensions

extension String {

    public var reversedData: Data? {
        return self.hs.hexData.map { Data($0.reversed()) }
    }

}
