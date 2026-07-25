import Foundation
import Starscream
import WalletConnectRelay

extension Starscream.WebSocket: @retroactive WebSocketConnecting {}

struct PeakSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        let socket = Starscream.WebSocket(url: url)
        socket.callbackQueue = DispatchQueue(
            label: "com.pranay.peak.wc.sockets",
            qos: .utility,
            attributes: .concurrent
        )
        return socket
    }
}
