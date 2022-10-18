import Foundation
import HdWalletKit

class PublicKeyFetcher {
    private let hdAccountWallet: HDAccountWallet

    init(hdAccountWallet: HDAccountWallet) {
        self.hdAccountWallet = hdAccountWallet
    }

}

extension PublicKeyFetcher: IPublicKeyFetcher {

    func publicKeys(indices: Range<UInt32>, external: Bool) throws -> [PublicKey] {
        try hdAccountWallet.publicKeys(indices: indices, external: external)
    }

}

class WatchPublicKeyFetcher {
    private let hdWatchAccountWallet: HDWatchAccountWallet

    init(hdWatchAccountWallet: HDWatchAccountWallet) {
        self.hdWatchAccountWallet = hdWatchAccountWallet
    }

}

extension WatchPublicKeyFetcher: IPublicKeyFetcher {

    func publicKeys(indices: Range<UInt32>, external: Bool) throws -> [PublicKey] {
        try hdWatchAccountWallet.publicKeys(indices: indices, external: external)
    }

}

class MultiAccountPublicKeyFetcher {
    private let hdWallet: HDWallet
    private(set) var currentAccount: Int = 0

    init(hdWallet: HDWallet) {
        self.hdWallet = hdWallet
    }

}

extension MultiAccountPublicKeyFetcher: IPublicKeyFetcher, IMultiAccountPublicKeyFetcher {

    func publicKeys(indices: Range<UInt32>, external: Bool) throws -> [PublicKey] {
        try hdWallet.publicKeys(account: currentAccount, indices: indices, external: external)
    }

    func increaseAccount() {
        currentAccount += 1
    }

}
