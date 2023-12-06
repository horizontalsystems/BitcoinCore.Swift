import Combine
import Foundation
import HsToolKit

public class BlockDownload {
    public weak var listener: IBlockSyncListener?
    private static let peerSwitchMinimumRatio = 1.5

    private var cancellables = Set<AnyCancellable>()
    private var blockSyncer: IBlockSyncer
    private let peerManager: IPeerManager
    private let merkleBlockValidator: IMerkleBlockValidator

    private var minMerkleBlocksCount: Double = 0
    private var minTransactionsCount: Double = 0
    private var minTransactionsSize: Double = 0
    private var slowPeersDisconnected = 0

    private let subject = PassthroughSubject<InitialDownloadEvent, Never>()

    private var syncedStates = [String: Bool]()

    private var selectNewPeer = false
    private let peersQueue: DispatchQueue
    private let logger: Logger?

    public var syncedPeers = [IPeer]()
    public var syncPeer: IPeer?

    init(blockSyncer: IBlockSyncer, peerManager: IPeerManager, merkleBlockValidator: IMerkleBlockValidator,
         peersQueue: DispatchQueue = DispatchQueue(label: "io.horizontalsystems.bitcoin-core.block-download", qos: .userInitiated),
         logger: Logger? = nil)
    {
        self.blockSyncer = blockSyncer
        self.peerManager = peerManager
        self.merkleBlockValidator = merkleBlockValidator
        self.peersQueue = peersQueue
        self.logger = logger
        resetRequiredDownloadSpeed()
    }

    public var publisher: AnyPublisher<InitialDownloadEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    private func syncedState(_ peer: IPeer) -> Bool {
        syncedStates[peer.host] ?? false
    }

    private func assignNextSyncPeer() {
        guard syncPeer == nil else {
            return
        }

        let nonSyncedPeers = peerManager.sorted.filter { !syncedState($0) }
        if nonSyncedPeers.isEmpty {
            subject.send(.onAllPeersSynced)
        }

        if let peer = nonSyncedPeers.first(where: { $0.ready }) {
            logger?.debug("Setting sync peer to \(peer.logName)")
            syncPeer = peer
            downloadBlockchain()
        }
    }

    private func downloadBlockchain() {
        guard let syncPeer, syncPeer.ready else {
            return
        }

        if selectNewPeer {
            selectNewPeer = false
            blockSyncer.downloadCompleted()
            self.syncPeer = nil
            assignNextSyncPeer()
            return
        }

        let blockHashes = blockSyncer.getBlockHashes(limit: 50)
        if blockHashes.isEmpty {
            syncedStates[syncPeer.host] = true
        } else {
            syncPeer.add(task: GetMerkleBlocksTask(
                blockHashes: blockHashes, merkleBlockValidator: merkleBlockValidator, merkleBlockHandler: self,
                minMerkleBlocksCount: minMerkleBlocksCount, minTransactionsCount: minTransactionsCount, minTransactionsSize: minTransactionsSize
            ))
        }

        if syncedState(syncPeer) {
            self.syncPeer = nil
            setPeerSynced(syncPeer)
            blockSyncer.downloadCompleted()
            syncPeer.sendMempoolMessage()
            assignNextSyncPeer()
        }
    }

    private func resetRequiredDownloadSpeed() {
        minMerkleBlocksCount = 500
        minTransactionsCount = 50000
        minTransactionsSize = 100_000
    }

    private func decreaseRequiredDownloadSpeed() {
        minMerkleBlocksCount = minMerkleBlocksCount / 3
        minTransactionsCount = minTransactionsCount / 3
        minTransactionsSize = minTransactionsSize / 3
    }

    private func setPeerSynced(_ peer: IPeer) {
        syncedStates[peer.host] = true
        syncedPeers.append(peer)
        subject.send(.onPeerSynced(peer: peer))
        listener?.blocksSyncFinished()
    }

    private func setPeerNotSynced(_ peer: IPeer) {
        syncedStates[peer.host] = false
        if let index = syncedPeers.firstIndex(where: { $0.equalTo(peer) }) {
            syncedPeers.remove(at: index)
        }
        subject.send(.onPeerNotSynced(peer: peer))
    }

    private func onStart() {
        resetRequiredDownloadSpeed()
        blockSyncer.prepareForDownload()
    }

    private func onStop() {}

    private func onRefresh() {
        peersQueue.async {
            if self.syncPeer == nil {
                for peer in self.peerManager.connected {
                    self.setPeerNotSynced(peer)
                }

                self.assignNextSyncPeer()
            }
        }
    }

    private func onPeerConnect(peer: IPeer) {
        peersQueue.async {
            self.syncedStates[peer.host] = false
            if let syncPeer = self.syncPeer, syncPeer.connectionTime > peer.connectionTime * BlockDownload.peerSwitchMinimumRatio {
                self.selectNewPeer = true
            }
            self.assignNextSyncPeer()
        }
    }

    private func onPeerDisconnect(peer: IPeer, error: Error?) {
        peersQueue.async {
            if error is GetMerkleBlocksTask.TooSlowPeer {
                self.slowPeersDisconnected += 1
                if self.slowPeersDisconnected >= 3 {
                    self.decreaseRequiredDownloadSpeed()
                    self.slowPeersDisconnected = 0
                }
            }

            if let index = self.syncedPeers.firstIndex(where: { $0.equalTo(peer) }) {
                self.syncedPeers.remove(at: index)
            }
            self.syncedStates.removeValue(forKey: peer.host)

            if peer.equalTo(self.syncPeer) {
                self.syncPeer = nil
                self.blockSyncer.downloadFailed()
                self.assignNextSyncPeer()
            }
        }
    }

    private func onPeerReady(peer: IPeer) {
        if peer.equalTo(syncPeer) {
            peersQueue.async {
                self.downloadBlockchain()
            }
        }
    }
}

extension BlockDownload: IInventoryItemsHandler {
    public func handleInventoryItems(peer _: IPeer, inventoryItems _: [InventoryItem]) {}
}

extension BlockDownload: IPeerTaskHandler {
    public func handleCompletedTask(peer _: IPeer, task: PeerTask) -> Bool {
        switch task {
        case is GetMerkleBlocksTask:
            blockSyncer.downloadIterationCompleted()
            return true
        default: return false
        }
    }
}

extension BlockDownload: IInitialDownload {
    public var hasSyncedPeer: Bool {
        syncedPeers.count > 0
    }

    public func isSynced(peer: IPeer) -> Bool {
        syncedState(peer)
    }

    public func subscribeTo(publisher: AnyPublisher<PeerGroupEvent, Never>) {
        publisher
            .sink { [weak self] event in
                switch event {
                case .onStart: self?.onStart()
                case .onStop: self?.onStop()
                case .onRefresh: self?.onRefresh()
                case let .onPeerConnect(peer): self?.onPeerConnect(peer: peer)
                case let .onPeerDisconnect(peer, error): self?.onPeerDisconnect(peer: peer, error: error)
                case let .onPeerReady(peer): self?.onPeerReady(peer: peer)
                default: ()
                }
            }
            .store(in: &cancellables)
    }
}

extension BlockDownload: IMerkleBlockHandler {
    func handle(merkleBlock: MerkleBlock) throws {
        let maxBlockHeight = syncPeer?.announcedLastBlockHeight ?? 0
        try blockSyncer.handle(merkleBlock: merkleBlock, maxBlockHeight: maxBlockHeight)
    }
}
