import Foundation
import HdWalletKit
import HsToolKit
import BigInt

public class BitcoinCore {
    private let storage: IStorage
    private var dataProvider: IDataProvider
    private let publicKeyManager: IPublicKeyManager
    private let watchedTransactionManager: IWatchedTransactionManager
    private let addressConverter: AddressConverterChain
    private let restoreKeyConverterChain: RestoreKeyConverterChain
    private let unspentOutputSelector: UnspentOutputSelectorChain

    private let transactionCreator: ITransactionCreator?
    private let transactionFeeCalculator: ITransactionFeeCalculator?
    private let dustCalculator: IDustCalculator?
    private let paymentAddressParser: IPaymentAddressParser

    private let networkMessageSerializer: NetworkMessageSerializer
    private let networkMessageParser: NetworkMessageParser

    private let syncManager: SyncManager
    private let pluginManager: IPluginManager

    private let purpose: Purpose
    private let peerManager: IPeerManager

    // START: Extending

    public let peerGroup: IPeerGroup
    public let initialDownload: IInitialDownload
    public let transactionSyncer: ITransactionSyncer

    let bloomFilterLoader: BloomFilterLoader
    let inventoryItemsHandlerChain = InventoryItemsHandlerChain()
    let peerTaskHandlerChain = PeerTaskHandlerChain()

    public func add(inventoryItemsHandler: IInventoryItemsHandler) {
        inventoryItemsHandlerChain.add(handler: inventoryItemsHandler)
    }

    public func add(peerTaskHandler: IPeerTaskHandler) {
        peerTaskHandlerChain.add(handler: peerTaskHandler)
    }

    public func add(restoreKeyConverter: IRestoreKeyConverter) {
        restoreKeyConverterChain.add(converter: restoreKeyConverter)
    }

    @discardableResult public func add(messageParser: IMessageParser) -> Self {
        networkMessageParser.add(parser: messageParser)
        return self
    }

    @discardableResult public func add(messageSerializer: IMessageSerializer) -> Self {
        networkMessageSerializer.add(serializer: messageSerializer)
        return self
    }

    public func add(plugin: IPlugin) {
        pluginManager.add(plugin: plugin)
    }

    func publicKey(byPath path: String) throws -> PublicKey {
        try publicKeyManager.publicKey(byPath: path)
    }

    public func prepend(addressConverter: IAddressConverter) {
        self.addressConverter.prepend(addressConverter: addressConverter)
    }

    public func prepend(unspentOutputSelector: IUnspentOutputSelector) {
        self.unspentOutputSelector.prepend(unspentOutputSelector: unspentOutputSelector)
    }

    // END: Extending

    public var delegateQueue = DispatchQueue(label: "io.horizontalsystems.bitcoin-core.bitcoin-core-delegate-queue")
    public weak var delegate: BitcoinCoreDelegate?

    init(storage: IStorage, dataProvider: IDataProvider,
         peerGroup: IPeerGroup, initialDownload: IInitialDownload, bloomFilterLoader: BloomFilterLoader, transactionSyncer: ITransactionSyncer,
         publicKeyManager: IPublicKeyManager, addressConverter: AddressConverterChain, restoreKeyConverterChain: RestoreKeyConverterChain,
         unspentOutputSelector: UnspentOutputSelectorChain,
         transactionCreator: ITransactionCreator?, transactionFeeCalculator: ITransactionFeeCalculator?, dustCalculator: IDustCalculator?,
         paymentAddressParser: IPaymentAddressParser, networkMessageParser: NetworkMessageParser, networkMessageSerializer: NetworkMessageSerializer,
         syncManager: SyncManager, pluginManager: IPluginManager, watchedTransactionManager: IWatchedTransactionManager, purpose: Purpose,
         peerManager: IPeerManager) {
        self.storage = storage
        self.dataProvider = dataProvider
        self.peerGroup = peerGroup
        self.initialDownload = initialDownload
        self.bloomFilterLoader = bloomFilterLoader
        self.transactionSyncer = transactionSyncer
        self.publicKeyManager = publicKeyManager
        self.addressConverter = addressConverter
        self.restoreKeyConverterChain = restoreKeyConverterChain
        self.unspentOutputSelector = unspentOutputSelector
        self.transactionCreator = transactionCreator
        self.transactionFeeCalculator = transactionFeeCalculator
        self.dustCalculator = dustCalculator
        self.paymentAddressParser = paymentAddressParser

        self.networkMessageParser = networkMessageParser
        self.networkMessageSerializer = networkMessageSerializer

        self.syncManager = syncManager
        self.pluginManager = pluginManager
        self.watchedTransactionManager = watchedTransactionManager

        self.purpose = purpose
        self.peerManager = peerManager
    }

}

extension BitcoinCore {

    public func start() {
        syncManager.start()
    }

    func stop() {
        syncManager.stop()
    }

}

extension BitcoinCore {

    public var watchAccount: Bool { //todo: What is better way to determine watch?
        transactionCreator == nil
    }

    public var lastBlockInfo: BlockInfo? {
        dataProvider.lastBlockInfo
    }

    public var balance: BalanceInfo {
        dataProvider.balance
    }

    public var syncState: BitcoinCore.KitState {
        syncManager.syncState
    }

    public func transactions(fromUid: String? = nil, type: TransactionFilterType?, limit: Int? = nil) -> [TransactionInfo] {
        dataProvider.transactions(fromUid: fromUid, type: type, limit: limit)
    }

    public func transaction(hash: String) -> TransactionInfo? {
        dataProvider.transaction(hash: hash)
    }

    public func send(to address: String, value: Int, feeRate: Int, sortType: TransactionDataSortType, pluginData: [UInt8: IPluginData] = [:]) throws -> FullTransaction {
        guard let transactionCreator = transactionCreator else {
            throw CoreError.readOnlyCore
        }

        return try transactionCreator.create(to: address, value: value, feeRate: feeRate, senderPay: true, sortType: sortType, pluginData: pluginData)
    }

    public func send(to hash: Data, scriptType: ScriptType, value: Int, feeRate: Int, sortType: TransactionDataSortType) throws -> FullTransaction {
        guard let transactionCreator = transactionCreator else {
            throw CoreError.readOnlyCore
        }

        let toAddress = try addressConverter.convert(lockingScriptPayload: hash, type: scriptType)
        return try transactionCreator.create(to: toAddress.stringValue, value: value, feeRate: feeRate, senderPay: true, sortType: sortType, pluginData: [:])
    }

    func redeem(from unspentOutput: UnspentOutput, to address: String, feeRate: Int, sortType: TransactionDataSortType) throws -> FullTransaction {
        guard let transactionCreator = transactionCreator else {
            throw CoreError.readOnlyCore
        }

        return try transactionCreator.create(from: unspentOutput, to: address, feeRate: feeRate, sortType: sortType)
    }

    public func createRawTransaction(to address: String, value: Int, feeRate: Int, sortType: TransactionDataSortType, pluginData: [UInt8: IPluginData] = [:]) throws -> Data {
        guard let transactionCreator = transactionCreator else {
            throw CoreError.readOnlyCore
        }

        return try transactionCreator.createRawTransaction(to: address, value: value, feeRate: feeRate, senderPay: true, sortType: sortType, pluginData: pluginData)
    }

    public func validate(address: String, pluginData: [UInt8: IPluginData] = [:]) throws {
        try pluginManager.validate(address: try addressConverter.convert(address: address), pluginData: pluginData)
    }

    public func parse(paymentAddress: String) -> BitcoinPaymentData {
        paymentAddressParser.parse(paymentAddress: paymentAddress)
    }

    public func fee(for value: Int, toAddress: String? = nil, feeRate: Int, pluginData: [UInt8: IPluginData] = [:]) throws -> Int {
        guard let transactionFeeCalculator = transactionFeeCalculator else {
            throw CoreError.readOnlyCore
        }

        return try transactionFeeCalculator.fee(for: value, feeRate: feeRate, senderPay: true, toAddress: toAddress, pluginData: pluginData)
    }

    public func maxSpendableValue(toAddress: String? = nil, feeRate: Int, pluginData: [UInt8: IPluginData] = [:]) throws -> Int {
        guard let transactionFeeCalculator = transactionFeeCalculator else {
            throw CoreError.readOnlyCore
        }

        let sendAllFee = try transactionFeeCalculator.fee(for: balance.spendable, feeRate: feeRate, senderPay: false, toAddress: toAddress, pluginData: pluginData)
        return max(0, balance.spendable - sendAllFee)
    }

    public func minSpendableValue(toAddress: String? = nil) throws -> Int {
        guard let dustCalculator = dustCalculator else {
            throw CoreError.readOnlyCore
        }

        var scriptType = ScriptType.p2pkh
        if let addressStr = toAddress, let address = try? addressConverter.convert(address: addressStr) {
            scriptType = address.scriptType
        }

        return dustCalculator.dust(type: scriptType)
    }

    public func maxSpendLimit(pluginData: [UInt8: IPluginData]) throws -> Int? {
        try pluginManager.maxSpendLimit(pluginData: pluginData)
    }

    public func receiveAddress() -> String {
        guard let publicKey = try? publicKeyManager.receivePublicKey(),
              let address = try? addressConverter.convert(publicKey: publicKey, type: purpose.scriptType) else {
            return ""
        }

        return address.stringValue
    }

    public func changePublicKey() throws -> PublicKey {
        try publicKeyManager.changePublicKey()
    }

    public func receivePublicKey() throws -> PublicKey {
        try publicKeyManager.receivePublicKey()
    }

    func watch(transaction: BitcoinCore.TransactionFilter, delegate: IWatchedTransactionDelegate) {
        watchedTransactionManager.add(transactionFilter: transaction, delegatedTo: delegate)
    }

    public func debugInfo(network: INetwork) -> String {
        dataProvider.debugInfo(network: network, scriptType: purpose.scriptType, addressConverter: addressConverter)
    }

    public var statusInfo: [(String, Any)] {
        var status = [(String, Any)]()
        status.append(("state", syncManager.syncState.toString()))
        status.append(("synced until", ((lastBlockInfo?.timestamp.map { Double($0) })?.map { Date(timeIntervalSince1970: $0) }) ?? "n/a"))
        status.append(("syncing peer", initialDownload.syncPeer?.host ?? "n/a"))
        status.append(("derivation", purpose.description))

        status.append(contentsOf:
            peerManager.connected.enumerated().map { (index, peer) in
                var peerStatus = [(String, Any)]()
                peerStatus.append(("status", initialDownload.isSynced(peer: peer) ? "synced" : "not synced"))
                peerStatus.append(("host", peer.host))
                peerStatus.append(("best block", peer.announcedLastBlockHeight))
                peerStatus.append(("user agent", peer.announcedLastBlockHeight))

                let tasks = peer.tasks
                if tasks.isEmpty {
                    peerStatus.append(("tasks", "no tasks"))
                } else {
                    peerStatus.append(("tasks", tasks.map { task in 
                        (String(describing: task), task.state)
                    }))
                }

                return ("peer \(index + 1)", peerStatus)
            }
        )

        return status
    }

    func rawTransaction(transactionHash: String) -> String? {
        dataProvider.rawTransaction(transactionHash: transactionHash)
    }

}

extension BitcoinCore: IDataProviderDelegate {

    func transactionsUpdated(inserted: [TransactionInfo], updated: [TransactionInfo]) {
        delegateQueue.async { [weak self] in
            if let kit = self {
                kit.delegate?.transactionsUpdated(inserted: inserted, updated: updated)
            }
        }
    }

    func transactionsDeleted(hashes: [String]) {
        delegateQueue.async { [weak self] in
            self?.delegate?.transactionsDeleted(hashes: hashes)
        }
    }

    func balanceUpdated(balance: BalanceInfo) {
        delegateQueue.async { [weak self] in
            if let kit = self {
                kit.delegate?.balanceUpdated(balance: balance)
            }
        }
    }

    func lastBlockInfoUpdated(lastBlockInfo: BlockInfo) {
        delegateQueue.async { [weak self] in
            if let kit = self {
                kit.delegate?.lastBlockInfoUpdated(lastBlockInfo: lastBlockInfo)
            }
        }
    }

}

extension BitcoinCore: ISyncManagerDelegate {
    func kitStateUpdated(state: KitState) {
        delegateQueue.async { [weak self] in
            self?.delegate?.kitStateUpdated(state: state)
        }
    }
}

public protocol BitcoinCoreDelegate: AnyObject {
    func transactionsUpdated(inserted: [TransactionInfo], updated: [TransactionInfo])
    func transactionsDeleted(hashes: [String])
    func balanceUpdated(balance: BalanceInfo)
    func lastBlockInfoUpdated(lastBlockInfo: BlockInfo)
    func kitStateUpdated(state: BitcoinCore.KitState)
}

extension BitcoinCoreDelegate {

    public func transactionsUpdated(inserted: [TransactionInfo], updated: [TransactionInfo]) {}
    public func transactionsDeleted(hashes: [String]) {}
    public func balanceUpdated(balance: BalanceInfo) {}
    public func lastBlockInfoUpdated(lastBlockInfo: BlockInfo) {}
    public func kitStateUpdated(state: BitcoinCore.KitState) {}

}

extension BitcoinCore {

    public enum KitState {
        case synced
        case apiSyncing(transactions: Int)
        case syncing(progress: Double)
        case notSynced(error: Error)

        func toString() -> String {
            switch self {
            case .synced: return "Synced"
            case .apiSyncing(let transactions): return "ApiSyncing-\(transactions)"
            case .syncing(let progress): return "Syncing-\(Int(progress * 100))"
            case .notSynced(let error): return "NotSynced-\(String(reflecting: error))"
            }
        }
    }

    public enum SyncMode: Equatable {
        case blockchair(key: String)        // Restore and sync from Blockchair API.
        case api                            // Restore and sync from API.
        case full                           // Sync from bip44Checkpoint. Api restore disabled
    }

    public enum TransactionFilter {
        case p2shOutput(scriptHash: Data)
        case outpoint(transactionHash: Data, outputIndex: Int)
    }

}

extension BitcoinCore.KitState: Equatable {

    public static func == (lhs: BitcoinCore.KitState, rhs: BitcoinCore.KitState) -> Bool {
        switch (lhs, rhs) {
        case (.synced, .synced):
            return true
        case (.apiSyncing(transactions: let leftCount), .apiSyncing(transactions: let rightCount)):
            return leftCount == rightCount
        case (.syncing(progress: let leftProgress), .syncing(progress: let rightProgress)):
            return leftProgress == rightProgress
        case (.notSynced(let lhsError), .notSynced(let rhsError)):
            return "\(lhsError)" == "\(rhsError)"
        default:
            return false
        }
    }

}

extension BitcoinCore {

    public enum CoreError: Error {
        case readOnlyCore
    }

    public enum StateError: Error {
        case notStarted
    }

}
