import Combine

class BloomFilterLoader: IBloomFilterManagerDelegate {
    private var cancellables = Set<AnyCancellable>()
    private let bloomFilterManager: IBloomFilterManager
    private var peerManager: IPeerManager

    init(bloomFilterManager: IBloomFilterManager, peerManager: IPeerManager) {
        self.bloomFilterManager = bloomFilterManager
        self.peerManager = peerManager
    }

    private func onPeerConnect(peer: IPeer) {
        if let bloomFilter = bloomFilterManager.bloomFilter {
            peer.filterLoad(bloomFilter: bloomFilter)
        }
    }

    func bloomFilterUpdated(bloomFilter: BloomFilter) {
        for peer in peerManager.connected {
            peer.filterLoad(bloomFilter: bloomFilter)
        }
    }

    func subscribeTo(publisher: AnyPublisher<PeerGroupEvent, Never>) {
        publisher
                .sink { [weak self] event in
                    switch event {
                    case .onPeerConnect(let peer): self?.onPeerConnect(peer: peer)
                    default: ()
                    }
                }
                .store(in: &cancellables)
    }

}
