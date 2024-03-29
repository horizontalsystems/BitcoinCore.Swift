import Foundation

public extension INetwork {
    var protocolVersion: Int32 { 70015 }
    var maxBlockSize: UInt32 { 1_000_000 }
    var serviceFullNode: UInt64 { 1 }

    var bip44Checkpoint: Checkpoint {
        try! Checkpoint(bundleName: bundleName, network: String(describing: type(of: self)), blockType: .bip44)
    }

    var lastCheckpoint: Checkpoint {
        try! Checkpoint(bundleName: bundleName, network: String(describing: type(of: self)), blockType: .last)
    }
}
