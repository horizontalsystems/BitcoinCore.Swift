import Foundation
import GRDB
import HsCryptoKit

public class PublicKey: Record {

    enum InitError: Error {
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

    public init(withAccount account: Int, index: Int, external: Bool, hdPublicKeyData data: Data) throws {
        self.account = account
        self.index = index
        self.external = external
        path = "\(account)/\(external ? 1 : 0)/\(index)"
        raw = data
        hashP2pkh = Crypto.ripeMd160Sha256(data)
        hashP2wpkhWrappedInP2sh = Crypto.ripeMd160Sha256(OpCode.segWitOutputScript(hashP2pkh, versionByte: 0))
        convertedForP2tr = try SchnorrHelper.tweakedOutputKey(publicKey: raw, format: .compressed)

        super.init()
    }

    override open class var databaseTableName: String {
        return "publicKeys"
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

    required init(row: Row) {
        path = row[Columns.path]
        account = row[Columns.account]
        index = row[Columns.index]
        external = row[Columns.external]
        raw = row[Columns.raw]
        hashP2pkh = row[Columns.keyHash]
        hashP2wpkhWrappedInP2sh = row[Columns.scriptHashForP2WPKH]
        convertedForP2tr = row[Columns.convertedForP2tr]

        super.init(row: row)
    }

    override open func encode(to container: inout PersistenceContainer) {
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
