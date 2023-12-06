public class BlockMedianTimeHelper {
    private let medianTimeSpan = 11
    private let storage: IStorage

    // This flag must be set ONLY when it's NOT possible to get needed blocks for median time calculation
    private let approximate: Bool

    public init(storage: IStorage, approximate: Bool = false) {
        self.storage = storage
        self.approximate = approximate
    }
}

extension BlockMedianTimeHelper: IBlockMedianTimeHelper {
    public var medianTimePast: Int? {
        storage.lastBlock.flatMap {
            if approximate {
                // The median time is 6 blocks earlier which is approximately equal to 1 hour.
                return $0.timestamp - 3600
            } else {
                return medianTimePast(block: $0)
            }
        }
    }

    public func medianTimePast(block: Block) -> Int? {
        let startIndex = block.height - medianTimeSpan + 1
        let median = storage.timestamps(from: startIndex, to: block.height)

        if block.height >= medianTimeSpan, median.count < medianTimeSpan {
            return nil
        }

        return median[median.count / 2]
    }
}
