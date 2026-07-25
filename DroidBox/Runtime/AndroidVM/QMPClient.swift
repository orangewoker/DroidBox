import Foundation
import Network

actor QMPClient {
    private let queue = DispatchQueue(label: "com.droidbox.qmp", qos: .userInitiated)
    private var connection: NWConnection?
    private var buffer = Data()
    private var nextID = 1

    func connect(host: String = "127.0.0.1", port: UInt16) async throws {
        disconnect()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw DroidBoxError.adbUnavailable }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        self.connection = connection; connection.start(queue: queue)
        let greeting = try await receiveObject()
        guard greeting["QMP"] != nil else { throw DroidBoxError.unsupported("QMP greeting 无效") }
        _ = try await execute("qmp_capabilities")
    }

    func disconnect() { connection?.cancel(); connection = nil; buffer.removeAll(keepingCapacity: true) }
    func pause() async throws { _ = try await execute("stop") }
    func resume() async throws { _ = try await execute("cont") }
    func reset() async throws { _ = try await execute("system_reset") }
    func quit() async throws { _ = try await execute("quit") }
    func status() async throws -> String { (try await execute("query-status")["return"] as? [String: Any])?["status"] as? String ?? "unknown" }

    private func execute(_ command: String, arguments: [String: Any]? = nil) async throws -> [String: Any] {
        let id = nextID; nextID += 1
        var object: [String: Any] = ["execute": command, "id": id]
        if let arguments { object["arguments"] = arguments }
        var data = try JSONSerialization.data(withJSONObject: object); data.append(contentsOf: [13, 10]); try await send(data)
        while true {
            let response = try await receiveObject()
            if let responseID = response["id"] as? Int, responseID == id {
                if let error = response["error"] as? [String: Any] { throw DroidBoxError.unsupported("QMP: \(error["desc"] as? String ?? "unknown error")") }
                return response
            }
        }
    }

    private func receiveObject() async throws -> [String: Any] {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]; buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw DroidBoxError.unsupported("QMP JSON 无效") }
                return object
            }
            buffer.append(try await receive())
        }
    }
    private func send(_ data: Data) async throws {
        guard let connection else { throw DroidBoxError.adbUnavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
    private func receive() async throws -> Data {
        guard let connection else { throw DroidBoxError.adbUnavailable }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else { continuation.resume(throwing: DroidBoxError.unsupported(complete ? "QMP 已断开" : "QMP 未返回数据")) }
            }
        }
    }
}
