import BigInt
import Combine
import Foundation
import HdWalletKit
import HsExtensions

class DataProvider {
    private var cancellables = Set<AnyCancellable>()

    private let storage: IStorage
    private let balanceProvider: IBalanceProvider
    private let transactionInfoConverter: ITransactionInfoConverter

    private let balanceUpdateSubject = PassthroughSubject<Void, Never>()

    public var balance: BalanceInfo {
        didSet {
            if !(oldValue == balance) {
                delegate?.balanceUpdated(balance: balance)
            }
        }
    }

    private let lastBlockInfoQueue = DispatchQueue(label: "io.horizontalsystems.bitcoin-core.data-provider.last-block-info", qos: .utility)
    private var _lastBlockInfo: BlockInfo?

    weak var delegate: IDataProviderDelegate?

    init(storage: IStorage, balanceProvider: IBalanceProvider, transactionInfoConverter: ITransactionInfoConverter, throttleTimeMilliseconds: Int = 500) {
        self.storage = storage
        self.balanceProvider = balanceProvider
        self.transactionInfoConverter = transactionInfoConverter
        balance = balanceProvider.balanceInfo
        _lastBlockInfo = storage.lastBlock.map { blockInfo(fromBlock: $0) }

        balanceUpdateSubject
            .throttle(for: .milliseconds(throttleTimeMilliseconds), scheduler: DispatchQueue.global(qos: .background), latest: true)
            .sink { [weak self] in
                self?.balance = balanceProvider.balanceInfo
            }
            .store(in: &cancellables)
    }

    private func blockInfo(fromBlock block: Block) -> BlockInfo {
        BlockInfo(
            headerHash: block.headerHash.hs.reversedHex,
            height: block.height,
            timestamp: block.timestamp
        )
    }
}

extension DataProvider: IBlockchainDataListener {
    func onUpdate(updated: [Transaction], inserted: [Transaction], inBlock block: Block?) {
        delegate?.transactionsUpdated(
            inserted: storage.fullInfo(forTransactions: inserted.map { TransactionWithBlock(transaction: $0, blockHeight: block?.height) }).map { transactionInfoConverter.transactionInfo(fromTransaction: $0) },
            updated: storage.fullInfo(forTransactions: updated.map { TransactionWithBlock(transaction: $0, blockHeight: block?.height) }).map { transactionInfoConverter.transactionInfo(fromTransaction: $0) }
        )

        balanceUpdateSubject.send()
    }

    func onDelete(transactionHashes: [String]) {
        delegate?.transactionsDeleted(hashes: transactionHashes)

        balanceUpdateSubject.send()
    }

    func onInsert(block: Block) {
        if block.height > (lastBlockInfo?.height ?? 0) {
            let lastBlockInfo = blockInfo(fromBlock: block)

            lastBlockInfoQueue.async {
                self._lastBlockInfo = lastBlockInfo
            }

            delegate?.lastBlockInfoUpdated(lastBlockInfo: lastBlockInfo)

            balanceUpdateSubject.send()
        }
    }
}

extension DataProvider: IDataProvider {
    var lastBlockInfo: BlockInfo? {
        lastBlockInfoQueue.sync {
            _lastBlockInfo
        }
    }

    func transactions(fromUid: String?, type: TransactionFilterType?, descending: Bool, limit: Int?) -> [TransactionInfo] {
        var resolvedTimestamp: Int? = nil
        var resolvedOrder: Int? = nil

        if let fromUid, let transaction = storage.validOrInvalidTransaction(byUid: fromUid) {
            resolvedTimestamp = transaction.timestamp
            resolvedOrder = transaction.order
        }

        let transactions = storage.validOrInvalidTransactionsFullInfo(fromTimestamp: resolvedTimestamp, fromOrder: resolvedOrder, descending: descending, type: type, limit: limit)

        return transactions.map { transactionInfoConverter.transactionInfo(fromTransaction: $0) }
    }

    func transaction(hash: String) -> TransactionInfo? {
        guard let hash = hash.reversedData else {
            return nil
        }

        guard let transactionFullInfo = storage.transactionFullInfo(byHash: hash) else {
            return nil
        }

        return transactionInfoConverter.transactionInfo(fromTransaction: transactionFullInfo)
    }

    func transactionInfo(from fullInfo: FullTransactionForInfo) -> TransactionInfo {
        transactionInfoConverter.transactionInfo(fromTransaction: fullInfo)
    }

    func debugInfo(network _: INetwork, scriptType: ScriptType, addressConverter: IAddressConverter) -> String {
        var lines = [String]()

        let pubKeys = storage.publicKeys().sorted(by: { $0.index < $1.index })

        for pubKey in pubKeys {
            lines.append("acc: \(pubKey.account) - inx: \(pubKey.index) - ext: \(pubKey.external) : \((try! addressConverter.convert(publicKey: pubKey, type: scriptType)).stringValue)")
        }
        lines.append("PUBLIC KEYS COUNT: \(pubKeys.count)")
        return lines.joined(separator: "\n")
    }

    func rawTransaction(transactionHash: String) -> String? {
        guard let hash = transactionHash.reversedData else {
            return nil
        }

        return storage.transactionFullInfo(byHash: hash)?.rawTransaction ??
            storage.invalidTransaction(byHash: hash)?.rawTransaction
    }
}
