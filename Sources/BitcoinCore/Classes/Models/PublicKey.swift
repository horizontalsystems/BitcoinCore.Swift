import Foundation
import GRDB
import HsCryptoKit

public class PublicKey: Record {
    public enum InitError: Error {
        case invalid
        case wrongNetwork
    }

    public let path: String
    public let account: Int
    public let index: Int
    public let external: Bool
    public let raw: Data
    public let hashP2pkh: Data
    public let hashP2wpkhWrappedInP2sh: Data
    public let convertedForP2tr: Data

    init(path: String, hashP2pkh: Data = Data(), hashP2wpkhWrappedInP2sh: Data = Data(), convertedForP2tr: Data = Data()) {
        self.path = path
        account = 0
        index = 0
        external = false
        raw = Data()
        self.hashP2pkh = hashP2pkh
        self.hashP2wpkhWrappedInP2sh = hashP2wpkhWrappedInP2sh
        self.convertedForP2tr = convertedForP2tr

        super.init()
    }

    public init(withAccount account: Int, index: Int, external: Bool, hdPublicKeyData data: Data) throws {
        self.account = account
        self.index = index
        self.external = external
        path = "\(account)/\(external ? 0 : 1)/\(index)"
        raw = data
        hashP2pkh = Crypto.ripeMd160Sha256(data)
        hashP2wpkhWrappedInP2sh = Crypto.ripeMd160Sha256(OpCode.segWitOutputScript(hashP2pkh, versionByte: 0))
        convertedForP2tr = try SchnorrHelper.tweakedOutputKey(publicKey: raw)

        super.init()
    }

    override open class var databaseTableName: String {
        "publicKeys"
    }

    enum Columns: String, ColumnExpression, CaseIterable {
        case path
        case account
        case index
        case external
        case raw
        case keyHash
        case scriptHashForP2WPKH
        case convertedForP2tr
    }

    required init(row: Row) throws {
        path = row[Columns.path]
        account = row[Columns.account]
        index = row[Columns.index]
        external = row[Columns.external]
        raw = row[Columns.raw]
        hashP2pkh = row[Columns.keyHash]
        hashP2wpkhWrappedInP2sh = row[Columns.scriptHashForP2WPKH]
        convertedForP2tr = row[Columns.convertedForP2tr]

        try super.init(row: row)
    }

    override open func encode(to container: inout PersistenceContainer) throws {
        container[Columns.path] = path
        container[Columns.account] = account
        container[Columns.index] = index
        container[Columns.external] = external
        container[Columns.raw] = raw
        container[Columns.keyHash] = hashP2pkh
        container[Columns.scriptHashForP2WPKH] = hashP2wpkhWrappedInP2sh
        container[Columns.convertedForP2tr] = convertedForP2tr
    }
}

extension PublicKey: Hashable {
    public static func == (lhs: PublicKey, rhs: PublicKey) -> Bool {
        lhs.path == rhs.path
    }

    public var hashValue: Int {
        path.hashValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
