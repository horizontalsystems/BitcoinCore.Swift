import GRDB

public class PeerAddress: Record {
    let ip: String
    var score: Int
    var connectionTime: Double?

    public init(ip: String, score: Int) {
        self.ip = ip
        self.score = score

        super.init()
    }

    override open class var databaseTableName: String {
        "peerAddresses"
    }

    enum Columns: String, ColumnExpression {
        case ip
        case score
        case connectionTime
    }

    required init(row: Row) throws {
        ip = row[Columns.ip]
        score = row[Columns.score]
        connectionTime = row[Columns.connectionTime]

        try super.init(row: row)
    }

    override open func encode(to container: inout PersistenceContainer) throws {
        container[Columns.ip] = ip
        container[Columns.score] = score
        container[Columns.connectionTime] = connectionTime
    }
}
