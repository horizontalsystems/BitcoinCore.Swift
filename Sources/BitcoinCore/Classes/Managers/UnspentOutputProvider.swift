class UnspentOutputProvider {
    let storage: IStorage
    let pluginManager: IPluginManager
    let confirmationsThreshold: Int

    // Confirmed incoming and all outgoing unspent outputs
    private var allUtxo: [UnspentOutput] {
        let lastBlockHeight = storage.lastBlock?.height ?? 0

        return storage.unspentOutputs()
            .filter { unspentOutput in
                // If a transaction is an outgoing transaction, then it can be used
                // even if it's not included in a block yet
                if unspentOutput.transaction.isOutgoing {
                    return true
                }

                // If a transaction is an incoming transaction, then it can be used
                // only if it's included in a block and has enough number of confirmations
                guard let blockHeight = unspentOutput.blockHeight else {
                    return false
                }

                return blockHeight <= lastBlockHeight - confirmationsThreshold + 1
            }
    }

    private var unspendableTimeLockedUtxo: [UnspentOutput] {
        allUtxo.filter { !pluginManager.isSpendable(unspentOutput: $0) }
    }

    private var unspendableNotRelayedUtxo: [UnspentOutput] {
        allUtxo.filter { $0.transaction.status != .relayed }
    }

    init(storage: IStorage, pluginManager: IPluginManager, confirmationsThreshold: Int) {
        self.storage = storage
        self.pluginManager = pluginManager
        self.confirmationsThreshold = confirmationsThreshold
    }
}

extension UnspentOutputProvider: IUnspentOutputProvider {
    func spendableUtxo(filters: UtxoFilters) -> [UnspentOutput] {
        allUtxo.filter { utxo in
            guard pluginManager.isSpendable(unspentOutput: utxo), utxo.transaction.status == .relayed else {
                return false
            }

            if let scriptTypes = filters.scriptTypes, !scriptTypes.contains(utxo.output.scriptType) {
                return false
            }

            if let outputsCount = filters.maxOutputsCountForInputs,
               storage.outputsCount(transactionHash: utxo.transaction.dataHash) > outputsCount
            {
                return false
            }

            return true
        }
    }

    // Only confirmed spendable outputs
    func confirmedSpendableUtxo(filters: UtxoFilters) -> [UnspentOutput] {
        let lastBlockHeight = storage.lastBlock?.height ?? 0

        return spendableUtxo(filters: filters)
            .filter { unspentOutput in
                guard let blockHeight = unspentOutput.blockHeight else {
                    return false
                }

                return blockHeight <= lastBlockHeight - confirmationsThreshold + 1
            }
    }
}

extension UnspentOutputProvider: IBalanceProvider {
    var balanceInfo: BalanceInfo {
        let spendable = spendableUtxo(filters: UtxoFilters()).map(\.output.value).reduce(0, +)
        let unspendableTimeLocked = unspendableTimeLockedUtxo.map(\.output.value).reduce(0, +)
        let unspendableNotRelayed = unspendableNotRelayedUtxo.map(\.output.value).reduce(0, +)

        return BalanceInfo(spendable: spendable, unspendableTimeLocked: unspendableTimeLocked, unspendableNotRelayed: unspendableNotRelayed)
    }
}
