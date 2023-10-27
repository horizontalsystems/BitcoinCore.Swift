public class BiApiBlockProvider: IApiTransactionProvider {
    private let restoreProvider: IApiTransactionProvider
    private let syncProvider: IApiTransactionProvider
    private let apiSyncStateManager: ApiSyncStateManager

    public init(restoreProvider: IApiTransactionProvider, syncProvider: IApiTransactionProvider, apiSyncStateManager: ApiSyncStateManager) {
        self.restoreProvider = restoreProvider
        self.syncProvider = syncProvider
        self.apiSyncStateManager = apiSyncStateManager
    }

    public func transactions(addresses: [String], stopHeight: Int?) async throws -> [ApiTransactionItem] {
        return apiSyncStateManager.restored
            ? try await syncProvider.transactions(addresses: addresses, stopHeight: stopHeight)
            : try await restoreProvider.transactions(addresses: addresses, stopHeight: stopHeight)
    }
}
