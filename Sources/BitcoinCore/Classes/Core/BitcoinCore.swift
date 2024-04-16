import BigInt
import Foundation
import HdWalletKit
import HsToolKit

public class BitcoinCore {
    private let storage: IStorage
    private var dataProvider: IDataProvider
    private let publicKeyManager: IPublicKeyManager
    private let watchedTransactionManager: IWatchedTransactionManager
    private let addressConverter: AddressConverterChain
    private let restoreKeyConverterChain: RestoreKeyConverterChain
    private let unspentOutputSelector: UnspentOutputSelectorChain

    private let transactionCreator: ITransactionCreator?
    private let transactionBuilder: ITransactionBuilder?
    private let transactionFeeCalculator: ITransactionFeeCalculator?
    private let replacementTransactionBuilder: ReplacementTransactionBuilder?
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
         transactionCreator: ITransactionCreator?, transactionFeeCalculator: ITransactionFeeCalculator?, transactionBuilder: ITransactionBuilder?, replacementTransactionBuilder: ReplacementTransactionBuilder?, dustCalculator: IDustCalculator?,
         paymentAddressParser: IPaymentAddressParser, networkMessageParser: NetworkMessageParser, networkMessageSerializer: NetworkMessageSerializer,
         syncManager: SyncManager, pluginManager: IPluginManager, watchedTransactionManager: IWatchedTransactionManager, purpose: Purpose,
         peerManager: IPeerManager)
    {
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
        self.transactionBuilder = transactionBuilder
        self.replacementTransactionBuilder = replacementTransactionBuilder
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

public extension BitcoinCore {
    var watchAccount: Bool { // TODO: What is better way to determine watch?
        transactionCreator == nil
    }

    var lastBlockInfo: BlockInfo? {
        dataProvider.lastBlockInfo
    }

    var balance: BalanceInfo {
        dataProvider.balance
    }

    var syncState: BitcoinCore.KitState {
        syncManager.syncState
    }

    func transactions(fromUid: String? = nil, type: TransactionFilterType?, limit: Int? = nil) -> [TransactionInfo] {
        dataProvider.transactions(fromUid: fromUid, type: type, limit: limit)
    }

    func transaction(hash: String) -> TransactionInfo? {
        dataProvider.transaction(hash: hash)
    }

    var unspentOutputs: [UnspentOutput] {
        unspentOutputSelector.all
    }

    var unspentOutputsInfo: [UnspentOutputInfo] {
        unspentOutputSelector.all.map {
            .init(
                outputIndex: $0.output.index,
                transactionHash: $0.output.transactionHash,
                timestamp: TimeInterval($0.transaction.timestamp),
                address: $0.output.address,
                value: $0.output.value
            )
        }
    }

    func address(fromHash hash: Data, scriptType: ScriptType) throws -> Address {
        try addressConverter.convert(lockingScriptPayload: hash, type: scriptType)
    }

    func send(params: SendParameters) throws -> FullTransaction {
        guard let transactionCreator else {
            throw CoreError.readOnlyCore
        }

        return try transactionCreator.create(params: params)
    }

    internal func redeem(from unspentOutput: UnspentOutput, params: SendParameters) throws -> FullTransaction {
        guard let transactionCreator else {
            throw CoreError.readOnlyCore
        }

        return try transactionCreator.create(from: unspentOutput, params: params)
    }

    func createRawTransaction(params: SendParameters) throws -> Data {
        guard let transactionCreator else {
            throw CoreError.readOnlyCore
        }

        return try transactionCreator.createRawTransaction(params: params)
    }

    func validate(address: String, pluginData: [UInt8: IPluginData] = [:]) throws {
        try pluginManager.validate(address: addressConverter.convert(address: address), pluginData: pluginData)
    }

    func parse(paymentAddress: String) -> BitcoinPaymentData {
        paymentAddressParser.parse(paymentAddress: paymentAddress)
    }

    func sendInfo(params: SendParameters) throws -> BitcoinSendInfo {
        guard let transactionFeeCalculator else {
            throw CoreError.readOnlyCore
        }

//        if let t = try transactionBuilder?.buildTransaction(params: params) {
//            print(TransactionSerializer.serialize(transaction: t.build()).hs.hex)
//        }
        return try transactionFeeCalculator.sendInfo(params: params)
    }

    func maxSpendableValue(params: SendParameters) throws -> Int {
        guard let transactionFeeCalculator else {
            throw CoreError.readOnlyCore
        }

        let outputs = params.unspentOutputs.map { $0.outputs(from: unspentOutputSelector.all) }
        let balance = outputs.map { $0.map(\.output.value).reduce(0, +) } ?? balance.spendable

        params.value = balance
        params.senderPay = false
        let sendAllFee = try transactionFeeCalculator.sendInfo(params: params).fee

        return max(0, balance - sendAllFee)
    }

    func minSpendableValue(params: SendParameters) throws -> Int {
        guard let dustCalculator else {
            throw CoreError.readOnlyCore
        }

        var scriptType = ScriptType.p2pkh
        if let address = params.address, let address = try? addressConverter.convert(address: address) {
            scriptType = address.scriptType
        }

        return dustCalculator.dust(type: scriptType, dustThreshold: params.dustThreshold)
    }

    func maxSpendLimit(pluginData: [UInt8: IPluginData]) throws -> Int? {
        try pluginManager.maxSpendLimit(pluginData: pluginData)
    }

    func receiveAddress() -> String {
        guard let publicKey = try? publicKeyManager.receivePublicKey(),
              let address = try? addressConverter.convert(publicKey: publicKey, type: purpose.scriptType)
        else {
            return ""
        }

        return address.stringValue
    }

    func address(from publicKey: PublicKey) throws -> Address {
        try addressConverter.convert(publicKey: publicKey, type: purpose.scriptType)
    }

    func changePublicKey() throws -> PublicKey {
        try publicKeyManager.changePublicKey()
    }

    func receivePublicKey() throws -> PublicKey {
        try publicKeyManager.receivePublicKey()
    }

    func usedAddresses(change: Bool) -> [UsedAddress] {
        publicKeyManager.usedPublicKeys(change: change).compactMap { pubKey in
            let address = try? addressConverter.convert(publicKey: pubKey, type: purpose.scriptType)
            return address.map { UsedAddress(index: pubKey.index, address: $0.stringValue) }
        }
    }

    internal func watch(transaction: BitcoinCore.TransactionFilter, delegate: IWatchedTransactionDelegate) {
        watchedTransactionManager.add(transactionFilter: transaction, delegatedTo: delegate)
    }

    func replacementTransaction(transactionHash: String, minFee: Int, type: ReplacementType) throws -> ReplacementTransaction {
        guard let replacementTransactionBuilder else {
            throw CoreError.readOnlyCore
        }

        let (mutableTransaction, fullInfo, descendantTransactionHashes) = try replacementTransactionBuilder.replacementTransaction(transactionHash: transactionHash, minFee: minFee, type: type)
        let info = dataProvider.transactionInfo(from: fullInfo)

        return ReplacementTransaction(mutableTransaction: mutableTransaction, info: info, replacedTransactionHashes: descendantTransactionHashes)
    }

    func send(replacementTransaction: ReplacementTransaction) throws -> FullTransaction {
        guard let transactionCreator else {
            throw CoreError.readOnlyCore
        }

        return try transactionCreator.create(from: replacementTransaction.mutableTransaction)
    }

    func replacmentTransactionInfo(transactionHash: String, type: ReplacementType) -> (originalTransactionSize: Int, feeRange: Range<Int>)? {
        replacementTransactionBuilder?.replacementInfo(transactionHash: transactionHash, type: type)
    }

    func debugInfo(network: INetwork) -> String {
        dataProvider.debugInfo(network: network, scriptType: purpose.scriptType, addressConverter: addressConverter)
    }

    var statusInfo: [(String, Any)] {
        var status = [(String, Any)]()
        status.append(("sync mode", syncManager.syncMode.description))
        status.append(("state", syncManager.syncState.toString()))
        status.append(("synced until", ((lastBlockInfo?.timestamp.map { Double($0) })?.map { Date(timeIntervalSince1970: $0) }) ?? "n/a"))
        status.append(("syncing peer", initialDownload.syncPeer?.host ?? "n/a"))
        status.append(("derivation", purpose.description))

        status.append(contentsOf:
            peerManager.connected.enumerated().map { index, peer in
                var peerStatus = [(String, Any)]()
                peerStatus.append(("status", initialDownload.isSynced(peer: peer) ? "synced" : "not synced"))
                peerStatus.append(("host", peer.host))
                peerStatus.append(("best block", peer.announcedLastBlockHeight))
                peerStatus.append(("user agent", peer.subVersion))

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

    internal func rawTransaction(transactionHash: String) -> String? {
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

public extension BitcoinCoreDelegate {
    func transactionsUpdated(inserted _: [TransactionInfo], updated _: [TransactionInfo]) {}
    func transactionsDeleted(hashes _: [String]) {}
    func balanceUpdated(balance _: BalanceInfo) {}
    func lastBlockInfoUpdated(lastBlockInfo _: BlockInfo) {}
    func kitStateUpdated(state _: BitcoinCore.KitState) {}
}

public extension BitcoinCore {
    enum KitState {
        case synced
        case apiSyncing(transactions: Int)
        case syncing(progress: Double)
        case notSynced(error: Error)

        func toString() -> String {
            switch self {
            case .synced: return "Synced"
            case let .apiSyncing(transactions): return "ApiSyncing-\(transactions)"
            case let .syncing(progress): return "Syncing-\(Int(progress * 100))"
            case let .notSynced(error): return "NotSynced-\(String(reflecting: error))"
            }
        }
    }

    enum SyncMode: Equatable {
        case blockchair // Restore and sync from Blockchair API.
        case api // Restore and sync from API.
        case full // Sync from bip44Checkpoint. Api restore disabled

        var description: String {
            switch self {
            case .blockchair: return "Blockchair API"
            case .api: return "Hybrid"
            case .full: return "Blockchain"
            }
        }
    }

    enum SendType {
        case p2p
        case api(blockchairApi: BlockchairApi)
    }

    enum TransactionFilter {
        case p2shOutput(scriptHash: Data)
        case outpoint(transactionHash: Data, outputIndex: Int)
    }
}

extension BitcoinCore.KitState: Equatable {
    public static func == (lhs: BitcoinCore.KitState, rhs: BitcoinCore.KitState) -> Bool {
        switch (lhs, rhs) {
        case (.synced, .synced):
            return true
        case let (.apiSyncing(transactions: leftCount), .apiSyncing(transactions: rightCount)):
            return leftCount == rightCount
        case let (.syncing(progress: leftProgress), .syncing(progress: rightProgress)):
            return leftProgress == rightProgress
        case let (.notSynced(lhsError), .notSynced(rhsError)):
            return "\(lhsError)" == "\(rhsError)"
        default:
            return false
        }
    }
}

public extension BitcoinCore {
    enum CoreError: Error {
        case readOnlyCore
    }

    enum StateError: Error {
        case notStarted
    }
}

public extension BitcoinCore {
    static func firstAddress(seed: Data, purpose: Purpose, network: INetwork, addressCoverter: AddressConverterChain) throws -> Address {
        let wallet = HDWallet(seed: seed, coinType: network.coinType, xPrivKey: network.xPrivKey, purpose: purpose)
        let publicKey: PublicKey = try wallet.publicKey(account: 0, index: 0, external: true)

        return try addressCoverter.convert(publicKey: publicKey, type: purpose.scriptType)
    }

    static func firstAddress(extendedKey: HDExtendedKey, purpose: Purpose, network: INetwork, addressCoverter: AddressConverterChain) throws -> Address {
        let publicKey: PublicKey
        switch extendedKey {
        case let .private(key: privateKey):
            switch extendedKey.derivedType {
            case .master:
                let wallet = HDWallet(masterKey: privateKey, coinType: network.coinType, purpose: purpose)
                publicKey = try wallet.publicKey(account: 0, index: 0, external: true)
            case .account:
                let wallet = HDAccountWallet(privateKey: privateKey)
                publicKey = try wallet.publicKey(index: 0, external: true)
            case .bip32:
                throw BitcoinCoreBuilder.BuildError.notSupported
            }

        case let .public(key: hdPublicKey):
            let wallet = HDWatchAccountWallet(publicKey: hdPublicKey)
            publicKey = try wallet.publicKey(index: 0, external: true)
        }

        return try addressCoverter.convert(publicKey: publicKey, type: purpose.scriptType)
    }
}

public class SendParameters {
    var address: String?
    var value: Int?
    var feeRate: Int?
    var sortType: TransactionDataSortType
    var senderPay: Bool
    var rbfEnabled: Bool
    var memo: String?
    var unspentOutputs: [UnspentOutputInfo]?
    var pluginData: [UInt8: IPluginData]
    var dustThreshold: Int?
    var onlyStandardInputs: Bool
    var changeToFirstInput: Bool

    public init(
        address: String? = nil, value: Int? = nil, feeRate: Int? = nil, sortType: TransactionDataSortType = .none,
        senderPay: Bool = true, rbfEnabled: Bool = true, memo: String? = nil,
        unspentOutputs: [UnspentOutputInfo]? = nil, pluginData: [UInt8: IPluginData] = [:],
        dustThreshold: Int? = nil, onlyStandardInputs: Bool = false, changeToFirstInput: Bool = false
    ) {
        self.address = address
        self.value = value
        self.feeRate = feeRate
        self.sortType = sortType
        self.senderPay = senderPay
        self.rbfEnabled = rbfEnabled
        self.memo = memo
        self.unspentOutputs = unspentOutputs
        self.pluginData = pluginData
        self.dustThreshold = dustThreshold
        self.onlyStandardInputs = onlyStandardInputs
        self.changeToFirstInput = changeToFirstInput
    }
}
