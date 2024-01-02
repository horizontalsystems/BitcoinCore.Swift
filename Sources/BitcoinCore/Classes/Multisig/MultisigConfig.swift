import Foundation
import HdWalletKit

public struct MultisigConfig {
    public let cosignersCount: Int
    public let minSignaturesCount: Int
    public let scriptType: ScriptType
    public let keystores: [Keystore]

    public struct Keystore {
        let key: HDExtendedKey
        let words: [String]?
        let salt: String?
        let derivationPath: String?

        var isPublic: Bool {
            switch key {
                case .private: return false
                case .public: return true
            }
        }

        public init(key: HDExtendedKey, derivationPath: String? = nil) throws {
            if case .private = key, case .master = key.derivedType, derivationPath == nil {
                throw MultisigConfigError.noDerivationPath
            }

            self.key = key
            self.words = nil
            self.salt = nil
            self.derivationPath = derivationPath
        }

        public init(words: [String], passphrase: String, derivationPath: String) throws {
            guard let seed = Mnemonic.seed(mnemonic: words, passphrase: passphrase) else {
                throw MultisigConfigError.invalidMnemonicSeed
            }

            self.key = .private(key: HDPrivateKey(seed: seed, xPrivKey: HDExtendedKeyVersion.xprv.rawValue))
            self.words = words
            self.salt = passphrase
            self.derivationPath = derivationPath
        }
    }
}

public extension MultisigConfig {
    static func derivationPath(scriptType: ScriptType, coinType: UInt32, account: UInt32? = nil) throws -> String {
        switch scriptType {
            case .p2sh:
                return "m/45'"
            case .p2wsh:
                guard let account else {
                    throw MultisigConfigError.noAccount
                }

                return "m/48'/\(coinType)'/\(account)'/2'"
            case .p2wshSh:
                guard let account else {
                    throw MultisigConfigError.noAccount
                }

                return "m/48'/\(coinType)'/\(account)'/1'"
            case .p2pk, .p2pkh, .p2wpkh, .p2wpkhSh, .p2tr, .nullData, .unknown:
                throw MultisigConfigError.scriptTypeNotSupported
        }
    }

    static func sortedLastHardenedPublicKeys(keystores: [Keystore], coinType: UInt32) throws -> [HDPublicKey] {
        let publicKeys = try keystores.map { keystore in
            switch keystore.key {
                case .private(let key):
                    switch keystore.key.derivedType {
                        case .master:
                            guard let path = keystore.derivationPath else {
                                throw MultisigConfigError.noDerivationPath
                            }

                            let wallet = HDWallet(masterKey: key, coinType: coinType, purpose: .bip44)
                            let publicKey = try wallet.privateKey(path: path).publicKey()
                            return publicKey
                        case .account:
                            return key.publicKey()
                        case .bip32:
                            throw MultisigConfigError.keyNotSupported
                    }
                case .public(let key):
                    return key
            }
        }

        return publicKeys.sorted(by: { $0.raw.hs.hex < $1.raw.hs.hex })
    }

    enum MultisigConfigError: Error {
        case invalidMnemonicSeed
        case noAccount
        case noDerivationPath
        case keyNotSupported
        case scriptTypeNotSupported
    }
}
