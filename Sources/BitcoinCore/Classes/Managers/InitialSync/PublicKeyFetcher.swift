import Foundation
import HdWalletKit

class PublicKeyFetcher {
    private let hdAccountWallet: HDAccountWallet
    let gapLimit: Int

    init(hdAccountWallet: HDAccountWallet, gapLimit: Int = 5) {
        self.hdAccountWallet = hdAccountWallet
        self.gapLimit = gapLimit
    }

}

extension PublicKeyFetcher: IPublicKeyFetcher {

    func publicKeys(indices: Range<UInt32>, external: Bool) throws -> [PublicKey] {
        try hdAccountWallet.publicKeys(indices: indices, external: external)
    }

}

class ReadOnlyPublicKeyFetcher {
    private let readOnlyAccountWallet: ReadOnlyHDWallet
    let gapLimit: Int

    init(readOnlyAccountWallet: ReadOnlyHDWallet, gapLimit: Int = 5) {
        self.readOnlyAccountWallet = readOnlyAccountWallet
        self.gapLimit = gapLimit
    }

}

extension ReadOnlyPublicKeyFetcher: IPublicKeyFetcher {

    func publicKeys(indices: Range<UInt32>, external: Bool) throws -> [PublicKey] {
        []//try readOnlyAccountWallet.publicKeys(indices: indices, external: external)
    }

}

class MultiAccountPublicKeyFetcher {
    private let hdWallet: HDWallet
    let gapLimit: Int
    private(set) var currentAccount: Int = 0

    init(hdWallet: HDWallet, gapLimit: Int = 5) {
        self.hdWallet = hdWallet
        self.gapLimit = gapLimit
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
