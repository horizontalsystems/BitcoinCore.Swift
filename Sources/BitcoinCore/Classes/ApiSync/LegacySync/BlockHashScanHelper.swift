protocol IBlockHashScanHelper {
    func lastUsedIndex(addresses: [[String]], items: [ApiAddressItem]) -> Int
}

class BlockHashScanHelper: IBlockHashScanHelper {
    func lastUsedIndex(addresses: [[String]], items: [ApiAddressItem]) -> Int {
        guard addresses.count > 0 else {
            return -1
        }

        let searchAddressStrings = items.map { $0.address }
        let searchScriptStrings = items.map { $0.script }

        let lastIndex = addresses.count - 1
        for i in 0 ... lastIndex {
            for address in addresses[lastIndex - i] {
                if searchAddressStrings.contains(address) ||
                    searchScriptStrings.firstIndex(where: { script in script.contains(address) }) != nil
                {
                    return lastIndex - i
                }
            }
        }
        return -1
    }
}

class WatchAddressBlockHashScanHelper: IBlockHashScanHelper {
    func lastUsedIndex(addresses: [[String]], items: [ApiAddressItem]) -> Int { -1 }
}
