import Foundation
import HdWalletKit
import HsToolKit

public class BitcoinCoreBuilder {
    public enum BuildError: Error { case peerSizeLessThanRequired, noSeedData, noPurpose, noWalletId, noNetwork, noPaymentAddressParser, noAddressSelector, noStorage, noApiProvider, notSupported, noApiSyncStateManager, noCheckpoint }

    // chains
    public let addressConverter = AddressConverterChain()

    // required parameters
    private var extendedKey: HDExtendedKey?
    private var purpose: Purpose?
    private var network: INetwork?
    private var paymentAddressParser: IPaymentAddressParser?
    private var walletId: String?
    private var apiTransactionProvider: IApiTransactionProvider?
    private var plugins = [IPlugin]()
    private var logger: Logger

    private var blockHeaderHasher: IHasher?
    private var blockValidator: IBlockValidator?
    private var transactionInfoConverter: ITransactionInfoConverter?

    // parameters with default values
    private var confirmationsThreshold = 6
    private var syncMode = BitcoinCore.SyncMode.api
    private var peerCount = 10
    private var peerCountToConnect = 100

    private var storage: IStorage?
    private var checkpoint: Checkpoint?
    private var apiSyncStateManager: ApiSyncStateManager?

    @discardableResult public func set(extendedKey: HDExtendedKey) -> BitcoinCoreBuilder {
        self.extendedKey = extendedKey
        return self
    }

    public func set(network: INetwork) -> BitcoinCoreBuilder {
        self.network = network
        return self
    }

    public func set(purpose: Purpose) -> BitcoinCoreBuilder {
        self.purpose = purpose
        return self
    }

    public func set(paymentAddressParser: PaymentAddressParser) -> BitcoinCoreBuilder {
        self.paymentAddressParser = paymentAddressParser
        return self
    }

    public func set(walletId: String) -> BitcoinCoreBuilder {
        self.walletId = walletId
        return self
    }

    public func set(confirmationsThreshold: Int) -> BitcoinCoreBuilder {
        self.confirmationsThreshold = confirmationsThreshold
        return self
    }

    public func set(syncMode: BitcoinCore.SyncMode) -> BitcoinCoreBuilder {
        self.syncMode = syncMode
        return self
    }

    public func set(peerSize: Int) throws -> BitcoinCoreBuilder {
        guard peerSize >= TransactionSender.minConnectedPeersCount else {
            throw BuildError.peerSizeLessThanRequired
        }

        peerCount = peerSize
        return self
    }

    public func set(storage: IStorage) -> BitcoinCoreBuilder {
        self.storage = storage
        return self
    }

    public func set(checkpoint: Checkpoint) -> BitcoinCoreBuilder {
        self.checkpoint = checkpoint
        return self
    }

    public func set(apiSyncStateManager: ApiSyncStateManager) -> BitcoinCoreBuilder {
        self.apiSyncStateManager = apiSyncStateManager
        return self
    }

    public func set(blockHeaderHasher: IHasher) -> BitcoinCoreBuilder {
        self.blockHeaderHasher = blockHeaderHasher
        return self
    }

    public func set(blockValidator: IBlockValidator) -> BitcoinCoreBuilder {
        self.blockValidator = blockValidator
        return self
    }

    public func set(transactionInfoConverter: ITransactionInfoConverter) -> BitcoinCoreBuilder {
        self.transactionInfoConverter = transactionInfoConverter
        return self
    }

    public func set(apiTransactionProvider: IApiTransactionProvider?) -> BitcoinCoreBuilder {
        self.apiTransactionProvider = apiTransactionProvider
        return self
    }

    public func add(plugin: IPlugin) -> BitcoinCoreBuilder {
        plugins.append(plugin)
        return self
    }

    public init(logger: Logger) {
        self.logger = logger
    }

    public func build() throws -> BitcoinCore {
        guard let extendedKey = extendedKey else {
            throw BuildError.noSeedData
        }
        guard let purpose = purpose else {
            throw BuildError.noPurpose
        }
        guard let network = network else {
            throw BuildError.noNetwork
        }
        guard let paymentAddressParser = paymentAddressParser else {
            throw BuildError.noPaymentAddressParser
        }
        guard let storage = storage else {
            throw BuildError.noStorage
        }
        guard let checkpoint = checkpoint else {
            throw BuildError.noCheckpoint
        }
        guard let apiTransactionProvider = apiTransactionProvider else {
            throw BuildError.noApiProvider
        }
        guard let apiSyncStateManager = apiSyncStateManager else {
            throw BuildError.noApiSyncStateManager
        }

        let scriptConverter = ScriptConverter()
        let restoreKeyConverterChain = RestoreKeyConverterChain()
        let pluginManager = PluginManager(scriptConverter: scriptConverter, logger: logger)

        plugins.forEach { pluginManager.add(plugin: $0) }

        let unspentOutputProvider = UnspentOutputProvider(storage: storage, pluginManager: pluginManager, confirmationsThreshold: confirmationsThreshold)
        var transactionInfoConverter = self.transactionInfoConverter ?? TransactionInfoConverter()
        transactionInfoConverter.baseTransactionInfoConverter = BaseTransactionInfoConverter(pluginManager: pluginManager)
        let dataProvider = DataProvider(storage: storage, balanceProvider: unspentOutputProvider, transactionInfoConverter: transactionInfoConverter)

        let reachabilityManager = ReachabilityManager()

        var hdWallet: IPrivateHDWallet?
        let publicKeyFetcher: IPublicKeyFetcher
        var multiAccountPublicKeyFetcher: IMultiAccountPublicKeyFetcher?
        let publicKeyManager: IPublicKeyManager & IBloomFilterProvider

        switch extendedKey {
        case .private(let privateKey):
            switch extendedKey.derivedType {
            case .master:
                let wallet = HDWallet(masterKey: privateKey, coinType: network.coinType, purpose: purpose)
                hdWallet = wallet
                let fetcher = MultiAccountPublicKeyFetcher(hdWallet: wallet)
                publicKeyFetcher = fetcher
                multiAccountPublicKeyFetcher = fetcher
                publicKeyManager = PublicKeyManager.instance(storage: storage, hdWallet: wallet, gapLimit: 20, restoreKeyConverter: restoreKeyConverterChain)
            case .account:
                let wallet = HDAccountWallet(privateKey: privateKey)
                hdWallet = wallet
                publicKeyFetcher = PublicKeyFetcher(hdAccountWallet: wallet)
                publicKeyManager = AccountPublicKeyManager.instance(storage: storage, hdWallet: wallet, gapLimit: 20, restoreKeyConverter: restoreKeyConverterChain)
            case .bip32:
                throw BuildError.notSupported
            }
        case .public(let publicKey):
            switch extendedKey.derivedType {
            case .account:
                let wallet = HDWatchAccountWallet(publicKey: publicKey)
                publicKeyFetcher = WatchPublicKeyFetcher(hdWatchAccountWallet: wallet)
                publicKeyManager = AccountPublicKeyManager.instance(storage: storage, hdWallet: wallet, gapLimit: 20, restoreKeyConverter: restoreKeyConverterChain)
            default: throw BuildError.notSupported
            }
        }

        let networkMessageParser = NetworkMessageParser(magic: network.magic)
        let networkMessageSerializer = NetworkMessageSerializer(magic: network.magic)

        let doubleShaHasher = DoubleShaHasher()
        let merkleBranch = MerkleBranch(hasher: doubleShaHasher)
        let merkleBlockValidator = MerkleBlockValidator(maxBlockSize: network.maxBlockSize, merkleBranch: merkleBranch)

        let factory = Factory(network: network, networkMessageParser: networkMessageParser, networkMessageSerializer: networkMessageSerializer)

        let pendingOutpointsProvider = PendingOutpointsProvider(storage: storage)

        let transactionMetadataExtractor = TransactionMetadataExtractor(storage: storage)
        let irregularOutputFinder = IrregularOutputFinder(storage: storage)
        let transactionInputExtractor = TransactionInputExtractor(storage: storage, scriptConverter: scriptConverter, addressConverter: addressConverter, logger: logger)
        let publicKeySetter = TransactionPublicKeySetter(storage: storage)
        let outputScriptTypeParser = OutputScriptTypeParser()
        let transactionAddressExtractor = TransactionOutputAddressExtractor(storage: storage, addressConverter: addressConverter)
        let transactionExtractor = TransactionExtractor(outputScriptTypeParser: outputScriptTypeParser, publicKeySetter: publicKeySetter, inputExtractor: transactionInputExtractor, metaDataExtractor: transactionMetadataExtractor, outputAddressExtractor: transactionAddressExtractor, pluginManager: pluginManager)
        let transactionInvalidator = TransactionInvalidator(storage: storage, transactionInfoConverter: transactionInfoConverter, listener: dataProvider)
        let transactionConflictResolver = TransactionConflictsResolver(storage: storage)
        let transactionsProcessorQueue = DispatchQueue(label: "io.horizontalsystems.bitcoin-core.transaction-processor", qos: .background)
        let blockTransactionProcessor = BlockTransactionProcessor(storage: storage, extractor: transactionExtractor, publicKeyManager: publicKeyManager, irregularOutputFinder: irregularOutputFinder, conflictsResolver: transactionConflictResolver, invalidator: transactionInvalidator, listener: dataProvider, queue: transactionsProcessorQueue)
        let pendingTransactionProcessor = PendingTransactionProcessor(storage: storage, extractor: transactionExtractor, publicKeyManager: publicKeyManager, irregularOutputFinder: irregularOutputFinder, conflictsResolver: transactionConflictResolver, listener: dataProvider, queue: transactionsProcessorQueue)

        let peerDiscovery = PeerDiscovery()
        let peerAddressManager = PeerAddressManager(storage: storage, dnsSeeds: network.dnsSeeds, peerDiscovery: peerDiscovery, logger: logger)
        peerDiscovery.peerAddressManager = peerAddressManager

        let peerManager = PeerManager()
        let unspentOutputSelector = UnspentOutputSelectorChain()
        let pendingTransactionSyncer = TransactionSyncer(storage: storage, processor: pendingTransactionProcessor, invalidator: transactionInvalidator, publicKeyManager: publicKeyManager)
        let watchedTransactionManager = WatchedTransactionManager()

        let blockHashScanner = BlockHashScanner(restoreKeyConverter: restoreKeyConverterChain, provider: apiTransactionProvider, helper: BlockHashScanHelper())

        let bloomFilterManager = BloomFilterManager(factory: factory)
        let bloomFilterLoader = BloomFilterLoader(bloomFilterManager: bloomFilterManager, peerManager: peerManager)
        let blockchain = Blockchain(storage: storage, blockValidator: blockValidator, factory: factory, listener: dataProvider)
        let blockSyncer = BlockSyncer.instance(storage: storage, checkpoint: checkpoint, factory: factory, transactionProcessor: blockTransactionProcessor, blockchain: blockchain, publicKeyManager: publicKeyManager, logger: logger)

        var apiSyncer: IApiSyncer
        let initialDownload: IInitialDownload

        if case .blockchair(let key) = syncMode {
            let blockchairApi: BlockchairApi

            if let provider = apiTransactionProvider as? BlockchairTransactionProvider {
                blockchairApi = provider.blockchairApi
            } else {
                blockchairApi = BlockchairApi(secretKey: key, chainId: network.blockchairChainId)
            }

            let lastBlockProvider = BlockchairLastBlockProvider(blockchairApi: blockchairApi)
            apiSyncer = BlockchairApiSyncer(storage: storage, gapLimit: 20, restoreKeyConverter: restoreKeyConverterChain,
                                            transactionProvider: apiTransactionProvider, lastBlockProvider: lastBlockProvider,
                                            publicKeyManager: publicKeyManager, blockchain: blockchain, apiSyncStateManager: apiSyncStateManager, logger: logger)

            initialDownload = BlockDownload(blockSyncer: blockSyncer, peerManager: peerManager, merkleBlockValidator: merkleBlockValidator, logger: logger)
        } else {
            let blockDiscoveryBatch = BlockDiscoveryBatch(checkpoint: checkpoint, gapLimit: 20, blockHashScanner: blockHashScanner, publicKeyFetcher: publicKeyFetcher)
            apiSyncer = ApiSyncer(storage: storage, blockDiscovery: blockDiscoveryBatch, publicKeyManager: publicKeyManager, multiAccountPublicKeyFetcher: multiAccountPublicKeyFetcher, apiSyncStateManager: apiSyncStateManager, logger: logger)

            initialDownload = InitialBlockDownload(blockSyncer: blockSyncer, peerManager: peerManager, merkleBlockValidator: merkleBlockValidator, logger: logger)
        }

        let peerGroup = PeerGroup(factory: factory, reachabilityManager: reachabilityManager, peerAddressManager: peerAddressManager, peerCount: peerCount, localDownloadedBestBlockHeight: blockSyncer.localDownloadedBestBlockHeight, peerManager: peerManager, logger: logger)
        let syncManager = SyncManager(reachabilityManager: reachabilityManager, apiSyncer: apiSyncer, peerGroup: peerGroup, storage: storage, syncMode: syncMode, bestBlockHeight: blockSyncer.localDownloadedBestBlockHeight)

        bloomFilterLoader.subscribeTo(publisher: peerGroup.publisher)
        blockSyncer.listener = syncManager
        initialDownload.listener = syncManager
        initialDownload.subscribeTo(publisher: peerGroup.publisher)

        bloomFilterManager.delegate = bloomFilterLoader
        bloomFilterManager.add(provider: watchedTransactionManager)
        bloomFilterManager.add(provider: publicKeyManager)
        bloomFilterManager.add(provider: pendingOutpointsProvider)
        bloomFilterManager.add(provider: irregularOutputFinder)

        apiSyncer.listener = syncManager
        blockHashScanner.listener = syncManager

        let transactionDataSorterFactory = TransactionDataSorterFactory()

        var dustCalculator: DustCalculator?
        var transactionSizeCalculator: TransactionSizeCalculator?
        var transactionFeeCalculator: TransactionFeeCalculator?
        var transactionSender: TransactionSender?
        var transactionCreator: TransactionCreator?

        if let hdWallet = hdWallet {
            let ecdsaInputSigner = EcdsaInputSigner(hdWallet: hdWallet, network: network)
            let schnorrInputSigner = SchnorrInputSigner(hdWallet: hdWallet)
            let transactionSizeCalculatorInstance = TransactionSizeCalculator()
            let dustCalculatorInstance = DustCalculator(dustRelayTxFee: network.dustRelayTxFee, sizeCalculator: transactionSizeCalculatorInstance)
            let recipientSetter = RecipientSetter(addressConverter: addressConverter, pluginManager: pluginManager)
            let outputSetter = OutputSetter(outputSorterFactory: transactionDataSorterFactory, factory: factory)
            let inputSetter = InputSetter(unspentOutputSelector: unspentOutputSelector, transactionSizeCalculator: transactionSizeCalculatorInstance, addressConverter: addressConverter, publicKeyManager: publicKeyManager, factory: factory, pluginManager: pluginManager, dustCalculator: dustCalculatorInstance, changeScriptType: purpose.scriptType, inputSorterFactory: transactionDataSorterFactory)
            let lockTimeSetter = LockTimeSetter(storage: storage)
            let transactionSigner = TransactionSigner(ecdsaInputSigner: ecdsaInputSigner, schnorrInputSigner: schnorrInputSigner)
            let transactionBuilder = TransactionBuilder(recipientSetter: recipientSetter, inputSetter: inputSetter, lockTimeSetter: lockTimeSetter, outputSetter: outputSetter, signer: transactionSigner)
            transactionFeeCalculator = TransactionFeeCalculator(recipientSetter: recipientSetter, inputSetter: inputSetter, addressConverter: addressConverter, publicKeyManager: publicKeyManager, changeScriptType: purpose.scriptType)
            let transactionSendTimer = TransactionSendTimer(interval: 60)
            let transactionSenderInstance = TransactionSender(transactionSyncer: pendingTransactionSyncer, initialBlockDownload: initialDownload, peerManager: peerManager, storage: storage, timer: transactionSendTimer, logger: logger)

            dustCalculator = dustCalculatorInstance
            transactionSizeCalculator = transactionSizeCalculatorInstance
            transactionSender = transactionSenderInstance

            transactionSendTimer.delegate = transactionSender

            transactionCreator = TransactionCreator(transactionBuilder: transactionBuilder, transactionProcessor: pendingTransactionProcessor, transactionSender: transactionSenderInstance, bloomFilterManager: bloomFilterManager)
        }
        let mempoolTransactions = MempoolTransactions(transactionSyncer: pendingTransactionSyncer, transactionSender: transactionSender)

        let bitcoinCore = BitcoinCore(storage: storage,
                                      dataProvider: dataProvider,
                                      peerGroup: peerGroup,
                                      initialDownload: initialDownload,
                                      bloomFilterLoader: bloomFilterLoader,
                                      transactionSyncer: pendingTransactionSyncer,
                                      publicKeyManager: publicKeyManager,
                                      addressConverter: addressConverter,
                                      restoreKeyConverterChain: restoreKeyConverterChain,
                                      unspentOutputSelector: unspentOutputSelector,
                                      transactionCreator: transactionCreator,
                                      transactionFeeCalculator: transactionFeeCalculator,
                                      dustCalculator: dustCalculator,
                                      paymentAddressParser: paymentAddressParser,
                                      networkMessageParser: networkMessageParser,
                                      networkMessageSerializer: networkMessageSerializer,
                                      syncManager: syncManager,
                                      pluginManager: pluginManager,
                                      watchedTransactionManager: watchedTransactionManager,
                                      purpose: purpose,
                                      peerManager: peerManager)

        dataProvider.delegate = bitcoinCore
        syncManager.delegate = bitcoinCore
        blockTransactionProcessor.transactionListener = watchedTransactionManager
        pendingTransactionProcessor.transactionListener = watchedTransactionManager

        peerGroup.peerTaskHandler = bitcoinCore.peerTaskHandlerChain
        peerGroup.inventoryItemsHandler = bitcoinCore.inventoryItemsHandlerChain

        bitcoinCore.prepend(addressConverter: Base58AddressConverter(addressVersion: network.pubKeyHash, addressScriptVersion: network.scriptHash))
        if let dustCalculator = dustCalculator, let transactionSizeCalculator = transactionSizeCalculator {
            bitcoinCore.prepend(unspentOutputSelector: UnspentOutputSelector(calculator: transactionSizeCalculator, provider: unspentOutputProvider, dustCalculator: dustCalculator))
            bitcoinCore.prepend(unspentOutputSelector: UnspentOutputSelectorSingleNoChange(calculator: transactionSizeCalculator, provider: unspentOutputProvider, dustCalculator: dustCalculator))
            // this part can be moved to another place
        }

        let blockHeaderParser = BlockHeaderParser(hasher: blockHeaderHasher ?? doubleShaHasher)
        bitcoinCore.add(messageParser: AddressMessageParser())
            .add(messageParser: GetDataMessageParser())
            .add(messageParser: InventoryMessageParser())
            .add(messageParser: PingMessageParser())
            .add(messageParser: PongMessageParser())
            .add(messageParser: VerackMessageParser())
            .add(messageParser: VersionMessageParser())
            .add(messageParser: MemPoolMessageParser())
            .add(messageParser: MerkleBlockMessageParser(blockHeaderParser: blockHeaderParser))
            .add(messageParser: TransactionMessageParser())

        bitcoinCore.add(messageSerializer: GetDataMessageSerializer())
            .add(messageSerializer: GetBlocksMessageSerializer())
            .add(messageSerializer: InventoryMessageSerializer())
            .add(messageSerializer: PingMessageSerializer())
            .add(messageSerializer: PongMessageSerializer())
            .add(messageSerializer: VerackMessageSerializer())
            .add(messageSerializer: MempoolMessageSerializer())
            .add(messageSerializer: VersionMessageSerializer())
            .add(messageSerializer: TransactionMessageSerializer())
            .add(messageSerializer: FilterLoadMessageSerializer())

        bitcoinCore.add(peerTaskHandler: initialDownload)
        bitcoinCore.add(inventoryItemsHandler: initialDownload)

        mempoolTransactions.subscribeTo(publisher: peerGroup.publisher)
        transactionSender?.subscribeTo(publisher: initialDownload.publisher)

        if let transactionSender = transactionSender {
            bitcoinCore.add(peerTaskHandler: transactionSender)
        }
        bitcoinCore.add(peerTaskHandler: mempoolTransactions)
        bitcoinCore.add(inventoryItemsHandler: mempoolTransactions)

        return bitcoinCore
    }
}
