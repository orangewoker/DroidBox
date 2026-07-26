import Foundation
import Network

/// Length-oriented TCP reads over `NWConnection`. `QMPClient` and `ADBClient` each grew
/// their own copy of this continuation dance; new transports use this instead.
actor ByteStream {
    private let queue: DispatchQueue
    private var connection: NWConnection?
    private var buffer = Data()

    init(label: String) { queue = DispatchQueue(label: label, qos: .userInitiated) }

    var isConnected: Bool { connection != nil }

    func connect(host: String, port: UInt16, timeout: Duration) async throws {
        close()
        try Task.checkCancellation()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw RFBError.invalidPort }
        let options = NWProtocolTCP.Options()
        options.noDelay = true
        options.connectionTimeout = max(1, Int(timeout.components.seconds))
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: endpointPort,
            using: NWParameters(tls: nil, tcp: options)
        )
        self.connection = connection
        do {
            // `withTaskCancellationHandler` is what lets a cancelled launch interrupt a
            // connect that would otherwise sit until the TCP timeout expires.
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let resumed = Resumed()
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if resumed.claim() { continuation.resume() }
                        case .failed(let error):
                            if resumed.claim() { continuation.resume(throwing: RFBError.disconnected(error.localizedDescription)) }
                        case .cancelled:
                            if resumed.claim() { continuation.resume(throwing: CancellationError()) }
                        default:
                            break
                        }
                    }
                    connection.start(queue: queue)
                }
            } onCancel: {
                connection.cancel()
            }
        } catch {
            close()
            throw error
        }
        connection.stateUpdateHandler = nil
    }

    func close() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: false)
    }

    func write(_ data: Data) async throws {
        guard let connection else { throw RFBError.disconnected("尚未连接") }
        guard !data.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: RFBError.disconnected(error.localizedDescription)) }
                else { continuation.resume() }
            })
        }
    }

    /// Reads exactly `count` bytes, buffering whatever the socket delivers beyond that.
    func read(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        while buffer.count < count {
            try Task.checkCancellation()
            buffer.append(try await receive(maximum: max(count - buffer.count, 32 * 1024)))
        }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    private func receive(maximum: Int) async throws -> Data {
        guard let connection else { throw RFBError.disconnected("尚未连接") }
        // The update loop spends nearly all its time parked here waiting for the guest to
        // draw, so cancellation has to tear the socket down rather than wait for data.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, complete, error in
                    if let error { continuation.resume(throwing: RFBError.disconnected(error.localizedDescription)) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: RFBError.disconnected(complete ? "远端关闭了连接" : "未收到数据")) }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

/// `NWConnection` may report several terminal states for one connection attempt; the
/// continuation must only be resumed for the first.
private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
