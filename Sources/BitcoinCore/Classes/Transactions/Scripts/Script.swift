import Foundation

public class Script {
    public let scriptData: Data
    public let chunks: [Chunk]

    public var length: Int { scriptData.count }

    public func validate(opCodes: Data) throws {
        guard opCodes.count == chunks.count else {
            throw ScriptError.wrongScriptLength
        }
        try chunks.enumerated().forEach { index, chunk in
            if chunk.opCode != opCodes[index] {
                throw ScriptError.wrongSequence
            }
        }
    }

    init(with data: Data, chunks: [Chunk]) {
        scriptData = data
        self.chunks = chunks
    }
}
