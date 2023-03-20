import Foundation
import HsToolKit

class OutputScriptTypeParser: ITransactionExtractor {

    func extract(transaction: FullTransaction) {
        for output in transaction.outputs {
            parseScriptType(output: output)
        }
    }

    func parseScriptType(output: Output) {
        var payload: Data?
        var validScriptType: ScriptType = .unknown
        
        let lockingScript = output.lockingScript
        let lockingScriptCount = lockingScript.count
        
        if lockingScriptCount == ScriptType.p2pkh.size,                                         // P2PKH Output script 25 bytes: 76 A9 14 {20-byte-key-hash} 88 AC
           lockingScript[0] == OpCode.dup,
           lockingScript[1] == OpCode.hash160,
           lockingScript[2] == 20,
           lockingScript[23] == OpCode.equalVerify,
           lockingScript[24] == OpCode.checkSig {
            // parse P2PKH transaction output
            payload = lockingScript.subdata(in: 3..<23)
            validScriptType = .p2pkh
        } else if lockingScriptCount == ScriptType.p2pk.size || lockingScriptCount == 67,       // P2PK Output script 35/67 bytes: {push-length-byte 33/65} {length-byte-public-key 33/65} AC
                  lockingScript[0] == 33 || lockingScript[0] == 65,
                  lockingScript[lockingScriptCount - 1] == OpCode.checkSig {
            // parse P2PK transaction output
            payload = lockingScript.subdata(in: 1..<(lockingScriptCount - 1))
            validScriptType = .p2pk
        } else if lockingScriptCount == ScriptType.p2sh.size,                                   // P2SH Output script 23 bytes: A9 14 {20-byte-script-hash} 87
                  lockingScript[0] == OpCode.hash160,
                  lockingScript[1] == 20,
                  lockingScript[lockingScriptCount - 1] == OpCode.equal {
            // parse P2SH transaction output
            payload = lockingScript.subdata(in: 2..<(lockingScriptCount - 1))
            validScriptType = .p2sh
        } else if lockingScriptCount == ScriptType.p2wpkh.size,                                // P2WPKH Output script 22 bytes: {version-byte {00} 14 {20-byte-key-hash}
                  lockingScript[0] == 0,                                                       // push version byte 0
                  lockingScript[1] == 20 {
            // parse P2WPKH transaction output
            payload = lockingScript.subdata(in: 2..<lockingScriptCount)
            validScriptType = .p2wpkh
        } else if lockingScriptCount == ScriptType.p2tr.size,                                  // P2TR Output script 34 bytes: {version-byte 51} {51} 20 {32-byte-public-key}
                  lockingScript[0] == 0x51,                                                      // push version byte 1 and
                  lockingScript[1] == 32 {
            // parse P2WPKH transaction output
            payload = lockingScript.subdata(in: 2..<lockingScriptCount)
            validScriptType = .p2tr
        } else if lockingScriptCount > 0 && lockingScript[0] == OpCode.op_return {             // nullData output
            payload = lockingScript.subdata(in: 0..<lockingScriptCount)
            validScriptType = .nullData
        }
        
        output.scriptType = validScriptType
        output.lockingScriptPayload = payload
    }

}
