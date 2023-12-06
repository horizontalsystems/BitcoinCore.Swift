import Foundation
import NIO

protocol PeerMessageHandlerDelegate: AnyObject {
    func onChannelActive()
    func onChannelInactive()
    func onChannelRead()
    func onMessageReceived(message: IMessage)
    func onErrorCaught(error: Error)
}

class PeerMessageHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var bufferSize = 4096
    private var packets: Data = .init()

    private let networkMessageParser: INetworkMessageParser

    weak var delegate: PeerMessageHandlerDelegate?

    init(networkMessageParser: INetworkMessageParser) {
        self.networkMessageParser = networkMessageParser
    }

    func channelActive(context _: ChannelHandlerContext) {
        delegate?.onChannelActive()
    }

    func channelInactive(context _: ChannelHandlerContext) {
        delegate?.onChannelInactive()
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        delegate?.onChannelRead()

        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readData(length: buffer.readableBytes) {
            packets += bytes
        }

        while packets.count >= NetworkMessage.minimumLength {
            guard let networkMessage = networkMessageParser.parse(data: packets) else {
                break
            }

            packets = Data(packets.dropFirst(NetworkMessage.minimumLength + Int(networkMessage.length)))
            let message = networkMessage.message

            guard !(message is UnknownMessage) else {
                continue
            }

            delegate?.onMessageReceived(message: message)
        }
    }

    func errorCaught(context _: ChannelHandlerContext, error: Error) {
        delegate?.onErrorCaught(error: error)
    }
}
