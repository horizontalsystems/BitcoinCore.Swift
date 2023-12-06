import Foundation

public enum SigHashType {
    case bitcoinAll
    case bitcoinTaprootAll
    case bitcoinCashAll

    var value: UInt8 {
        switch self {
        case .bitcoinAll: return 0x01
        case .bitcoinTaprootAll: return 0x00
        case .bitcoinCashAll: return 0x41
        }
    }

    var forked: Bool {
        switch self {
        case .bitcoinAll: return false
        case .bitcoinTaprootAll: return false
        case .bitcoinCashAll: return true
        }
    }
}
