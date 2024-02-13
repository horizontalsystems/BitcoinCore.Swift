import Foundation
import GRDB
import HsExtensions

public enum ScriptType: Int, DatabaseValueConvertible {
    case unknown, p2pkh, p2pk, p2multi, p2sh, p2wsh, p2wpkh, p2wpkhSh, p2tr, nullData

    var size: Int {
        switch self {
        case .p2pk: return 35
        case .p2pkh: return 25
        case .p2sh: return 23
        case .p2wsh: return 34
        case .p2wpkh: return 22
        case .p2wpkhSh: return 23
        case .p2tr: return 34
        default: return 0
        }
    }

    var witness: Bool {
        self == .p2wpkh || self == .p2wpkhSh || self == .p2wsh || self == .p2tr
    }
}

public class Output: Record {
    public var value: Int
    public var lockingScript: Data
    public var index: Int
    public var transactionHash: Data
    var publicKeyPath: String? = nil
    private(set) var changeOutput: Bool = false
    public var scriptType: ScriptType = .unknown
    public var redeemScript: Data? = nil
    public var lockingScriptPayload: Data? = nil
    var address: String? = nil
    var failedToSpend: Bool = false

    public var pluginId: UInt8? = nil
    public var pluginData: String? = nil
    public var signatureScriptFunction: (([Data]) -> Data)? = nil

    public func set(publicKey: PublicKey) {
        publicKeyPath = publicKey.path
        changeOutput = !publicKey.external
    }

    public init(original: Output) {
        value = original.value
        lockingScript = original.lockingScript
        index = original.index
        transactionHash = original.transactionHash
        publicKeyPath = original.publicKeyPath
        changeOutput = original.changeOutput
        scriptType = original.scriptType
        redeemScript = original.redeemScript
        lockingScriptPayload = original.lockingScriptPayload
        address = original.address
        failedToSpend = original.failedToSpend
        pluginId = original.pluginId
        pluginData = original.pluginData
        signatureScriptFunction = original.signatureScriptFunction

        super.init()
    }

    public init(withValue value: Int, index: Int, lockingScript script: Data, transactionHash: Data = Data(), type: ScriptType = .unknown, redeemScript: Data? = nil, address: String? = nil, lockingScriptPayload: Data? = nil, publicKey: PublicKey? = nil) {
        self.value = value
        lockingScript = script
        self.index = index
        self.transactionHash = transactionHash
        scriptType = type
        self.redeemScript = redeemScript
        self.address = address
        self.lockingScriptPayload = lockingScriptPayload

        super.init()

        if let publicKey {
            set(publicKey: publicKey)
        }
    }

    override open class var databaseTableName: String {
        "outputs"
    }

    enum Columns: String, ColumnExpression, CaseIterable {
        case value
        case lockingScript
        case index
        case transactionHash
        case publicKeyPath
        case changeOutput
        case scriptType
        case redeemScript
        case keyHash
        case address
        case pluginId
        case pluginData
        case failedToSpend
    }

    required init(row: Row) throws {
        value = row[Columns.value]
        lockingScript = row[Columns.lockingScript]
        index = row[Columns.index]
        transactionHash = row[Columns.transactionHash]
        publicKeyPath = row[Columns.publicKeyPath]
        changeOutput = row[Columns.changeOutput]
        scriptType = row[Columns.scriptType]
        redeemScript = row[Columns.redeemScript]
        lockingScriptPayload = row[Columns.keyHash]
        address = row[Columns.address]
        pluginId = row[Columns.pluginId]
        pluginData = row[Columns.pluginData]
        failedToSpend = row[Columns.failedToSpend]

        try super.init(row: row)
    }

    override open func encode(to container: inout PersistenceContainer) throws {
        container[Columns.value] = value
        container[Columns.lockingScript] = lockingScript
        container[Columns.index] = index
        container[Columns.transactionHash] = transactionHash
        container[Columns.publicKeyPath] = publicKeyPath
        container[Columns.changeOutput] = changeOutput
        container[Columns.scriptType] = scriptType
        container[Columns.redeemScript] = redeemScript
        container[Columns.keyHash] = lockingScriptPayload
        container[Columns.address] = address
        container[Columns.pluginId] = pluginId
        container[Columns.pluginData] = pluginData
        container[Columns.failedToSpend] = failedToSpend
    }
}

extension Output {
    var memo: String? {
        guard scriptType == .nullData, let payload = lockingScriptPayload, !payload.isEmpty, pluginId == nil else {
            return nil
        }

        // read first byte to get data length and parse first message
        let byteStream = ByteStream(payload)
        _ = byteStream.read(UInt8.self) // read op_return
        let length = byteStream.read(VarInt.self).underlyingValue
        if byteStream.availableBytes >= length {
            let data = byteStream.read(Data.self, count: Int(length))
            return String(data: data, encoding: .utf8) // TODO: make memo manager if need parse not only memo (some instructions)
        }

        return nil
    }
}
