import Combine
import HsToolKit

class SyncManager {
    private var cancellables = Set<AnyCancellable>()
    weak var delegate: ISyncManagerDelegate?

    private let reachabilityManager: ReachabilityManager
    private let initialSyncer: IInitialSyncer
    private let peerGroup: IPeerGroup
    private let apiSyncStateManager: IApiSyncStateManager

    private var initialBestBlockHeight: Int32
    private var currentBestBlockHeight: Int32
    private var foundTransactionsCount: Int = 0

    private(set) var syncState: BitcoinCore.KitState = .notSynced(error: BitcoinCore.StateError.notStarted) {
        didSet {
            if !(oldValue == syncState) {
                delegate?.kitStateUpdated(state: syncState)
            }
        }
    }

    private var syncIdle: Bool {
        guard case .notSynced(error: let error) = syncState else {
            return false
        }

        if let stateError = error as? BitcoinCore.StateError, stateError == .notStarted {
            return false
        }

        return true
    }

    private var peerGroupRunning: Bool {
        switch syncState {
        case .syncing, .synced: return true
        default: return false
        }
    }

    init(reachabilityManager: ReachabilityManager, initialSyncer: IInitialSyncer, peerGroup: IPeerGroup, apiSyncStateManager: IApiSyncStateManager, bestBlockHeight: Int32) {
        self.reachabilityManager = reachabilityManager
        self.initialSyncer = initialSyncer
        self.peerGroup = peerGroup
        self.apiSyncStateManager = apiSyncStateManager
        initialBestBlockHeight = bestBlockHeight
        currentBestBlockHeight = bestBlockHeight

        reachabilityManager.$isReachable
                .sink { [weak self] in
                    self?.onChange(isReachable: $0)
                }
                .store(in: &cancellables)

        reachabilityManager.connectionTypeChangedPublisher
                .sink { [weak self] _ in
                    self?.onConnectionTypeUpdated()
                }
                .store(in: &cancellables)

        BackgroundModeObserver.shared.foregroundFromExpiredBackgroundPublisher
                .sink { [weak self] _ in
                    self?.onEnterForegroundFromExpiredBackground()
                }
                .store(in: &cancellables)
    }

    private func onChange(isReachable: Bool) {
        if isReachable {
            onReachable()
        } else {
            onUnreachable()
        }
    }

    private func onConnectionTypeUpdated() {
        if peerGroupRunning {
            peerGroup.reconnectPeers()
        }
    }

    private func onEnterForegroundFromExpiredBackground() {
        if peerGroupRunning {
            peerGroup.reconnectPeers()
        }
    }

    private func onReachable() {
        if syncIdle {
            startSync()
        }
    }

    private func onUnreachable() {
        if peerGroupRunning {
            peerGroup.stop()
            syncState = .notSynced(error: ReachabilityManager.ReachabilityError.notReachable)
        }
    }

    private func startPeerGroup() {
        syncState = .syncing(progress: 0)
        peerGroup.start()
    }

    private func startInitialSync() {
        syncState = .apiSyncing(transactions: foundTransactionsCount)
        initialSyncer.sync()
    }

    private func startSync() {
        if apiSyncStateManager.restored {
            startPeerGroup()
        } else {
            startInitialSync()
        }
    }

}

extension SyncManager: ISyncManager {

    func start() {
        guard case .notSynced(_) = syncState else {
            return
        }

        guard reachabilityManager.isReachable else {
            syncState = .notSynced(error: ReachabilityManager.ReachabilityError.notReachable)
            return
        }

        startSync()
    }

    func stop() {
        switch syncState {
        case .apiSyncing:
            initialSyncer.terminate()
        case .syncing, .synced:
            peerGroup.stop()
        default: ()
        }

        syncState = .notSynced(error: BitcoinCore.StateError.notStarted)
    }

}

extension SyncManager: IInitialSyncerDelegate {

    func onSyncSuccess() {
        apiSyncStateManager.restored = true
        startPeerGroup()
    }

    func onSyncFailed(error: Error) {
        syncState = .notSynced(error: error)
    }

}


extension SyncManager: IApiSyncListener {

    func transactionsFound(count: Int) {
        foundTransactionsCount += count
        syncState = .apiSyncing(transactions: foundTransactionsCount)
    }

}

extension SyncManager: IBlockSyncListener {

    func blocksSyncFinished() {
        syncState = .synced
    }

    func currentBestBlockHeightUpdated(height: Int32, maxBlockHeight: Int32) {
        if currentBestBlockHeight < height {
            currentBestBlockHeight = height
        }

        let blocksDownloaded = currentBestBlockHeight - initialBestBlockHeight
        let allBlocksToDownload = maxBlockHeight - initialBestBlockHeight

        if allBlocksToDownload <= 0 || allBlocksToDownload <= blocksDownloaded {
            syncState = .synced
        } else {
            syncState = .syncing(progress: Double(blocksDownloaded) / Double(allBlocksToDownload))
        }
    }

}
