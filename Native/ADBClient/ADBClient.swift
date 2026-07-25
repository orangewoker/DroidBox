import Foundation
import Network

enum ADBClientError: LocalizedError, Sendable {
    case notConnected, connectionFailed(String), invalidPacket(String), authenticationRequired
    case serviceRejected(String), commandFailed(String), fileProtocol(String)
    var errorDescription: String? {
        switch self {
        case .notConnected: "ADB 尚未连接"
        case .connectionFailed(let value): "ADB 连接失败：\(value)"
        case .invalidPacket(let value): "ADB 协议数据无效：\(value)"
        case .authenticationRequired: "Android Runtime 要求 ADB RSA 认证，当前未授权 DroidBox"
        case .serviceRejected(let value): "ADB 服务拒绝请求：\(value)"
        case .commandFailed(let value): "ADB 命令失败：\(value)"
        case .fileProtocol(let value): "ADB 文件传输失败：\(value)"
        }
    }
}

actor ADBClient {
    private let queue = DispatchQueue(label: "com.droidbox.adb", qos: .userInitiated)
    private var connection: NWConnection?
    private var nextLocalID: UInt32 = 1
    private var maxPayload = 1_048_576

    func connect(host: String = "127.0.0.1", port: UInt16) async throws {
        disconnect()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw ADBClientError.connectionFailed("无效端口") }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        self.connection = connection; connection.start(queue: queue)
        let identity = Data("host::droidbox\0".utf8)
        try await send(ADBPacket(command: ADBPacket.connect, argument0: 0x01000001, argument1: UInt32(maxPayload), payload: identity))
        let response = try await receivePacket()
        if response.command == ADBPacket.authentication { disconnect(); throw ADBClientError.authenticationRequired }
        guard response.command == ADBPacket.connect else { disconnect(); throw ADBClientError.invalidPacket("expected CNXN") }
        maxPayload = min(maxPayload, max(4096, Int(response.argument1)))
    }

    func disconnect() { connection?.cancel(); connection = nil }
    func devices() throws -> String { guard connection != nil else { throw ADBClientError.notConnected }; return "emulator\tdevice\n" }
    func shell(_ command: String) async throws -> String { String(decoding: try await runService("shell:\(command)"), as: UTF8.self) }
    func logcat(arguments: String = "-d -v threadtime") async throws -> String { try await shell("logcat \(arguments)") }
    func uninstall(packageName: String) async throws { try validatePackage(packageName); try requireSuccess(try await shell("pm uninstall \(packageName)")) }
    func clearData(packageName: String) async throws { try validatePackage(packageName); try requireSuccess(try await shell("pm clear \(packageName)")) }
    func launch(packageName: String, activity: String) async throws {
        try validatePackage(packageName); guard !activity.contains(where: { $0.isWhitespace || $0 == ";" }) else { throw ADBClientError.commandFailed("Activity 名称无效") }
        let output = try await shell("am start -n \(packageName)/\(activity)")
        if output.localizedCaseInsensitiveContains("error") || output.localizedCaseInsensitiveContains("exception") { throw ADBClientError.commandFailed(output) }
    }
    func resolveLauncherActivity(packageName: String) async throws -> String {
        try validatePackage(packageName); let output = try await shell("cmd package resolve-activity --brief -c android.intent.category.LAUNCHER \(packageName)")
        guard let component = output.split(whereSeparator: \.isWhitespace).last, component.contains("/") else { throw DroidBoxError.activityNotFound }
        return String(component.split(separator: "/", maxSplits: 1)[1])
    }
    func gracefulShutdown() async throws { _ = try await shell("sync; reboot -p") }

    func install(apkURL: URL, replace: Bool = true) async throws {
        let remote = "/data/local/tmp/droidbox-\(UUID().uuidString).apk"
        try await push(localURL: apkURL, remotePath: remote)
        do {
            let output = try await shell("pm install \(replace ? "-r" : "") \(remote)")
            _ = try? await shell("rm -f \(remote)")
            guard output.contains("Success") else { throw ADBClientError.commandFailed(output) }
        } catch {
            _ = try? await shell("rm -f \(remote)")
            throw error
        }
    }

    func push(localURL: URL, remotePath: String, mode: UInt32 = 0o100644) async throws {
        let channel = try await openChannel("sync:")
        let specification = Data("\(remotePath),\(mode)".utf8)
        try await writeChannel(syncFrame("SEND", payload: specification), channel: channel)
        let handle = try FileHandle(forReadingFrom: localURL); defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: min(64 * 1024, maxPayload - 8)), !chunk.isEmpty {
            try Task.checkCancellation(); try await writeChannel(syncFrame("DATA", payload: chunk), channel: channel)
        }
        var done = Data("DONE".utf8); done.appendLittleEndian(UInt32(Date().timeIntervalSince1970))
        try await writeChannel(done, channel: channel)
        let response = try await readChannel(channel)
        guard response.starts(with: Data("OKAY".utf8)) else { throw ADBClientError.fileProtocol(syncFailure(response)) }
    }

    func pull(remotePath: String, localURL: URL) async throws {
        let channel = try await openChannel("sync:")
        try await writeChannel(syncFrame("RECV", payload: Data(remotePath.utf8)), channel: channel)
        let response = try await readChannel(channel); var cursor = 0, output = Data()
        while cursor + 8 <= response.count {
            let command = String(decoding: response[cursor..<cursor + 4], as: UTF8.self), length = Int(response.littleEndianUInt32(at: cursor + 4)); cursor += 8
            if command == "DONE" { try output.write(to: localURL, options: .atomic); return }
            if command == "FAIL" { throw ADBClientError.fileProtocol(String(decoding: response[cursor..<min(cursor + length, response.count)], as: UTF8.self)) }
            guard command == "DATA", cursor + length <= response.count else { throw ADBClientError.fileProtocol("无效 RECV 响应") }
            output.append(response[cursor..<cursor + length]); cursor += length
        }
        throw ADBClientError.fileProtocol("RECV 未正常结束")
    }

    private struct Channel: Sendable { let local: UInt32; let remote: UInt32 }
    private func runService(_ service: String) async throws -> Data { let channel = try await openChannel(service); return try await readChannel(channel) }
    private func openChannel(_ service: String) async throws -> Channel {
        let local = nextLocalID; nextLocalID &+= 1
        try await send(.init(command: ADBPacket.open, argument0: local, argument1: 0, payload: Data((service + "\0").utf8)))
        while true {
            let packet = try await receivePacket()
            if packet.command == ADBPacket.okay, packet.argument1 == local { return Channel(local: local, remote: packet.argument0) }
            if packet.command == ADBPacket.close { throw ADBClientError.serviceRejected(String(decoding: packet.payload, as: UTF8.self)) }
            if packet.command == ADBPacket.authentication { throw ADBClientError.authenticationRequired }
        }
    }
    private func writeChannel(_ data: Data, channel: Channel) async throws {
        var cursor = 0
        while cursor < data.count {
            let end = min(cursor + maxPayload, data.count)
            try await send(.init(command: ADBPacket.write, argument0: channel.local, argument1: channel.remote, payload: data[cursor..<end]))
            let response = try await receivePacket(); guard response.command == ADBPacket.okay else { throw ADBClientError.invalidPacket("WRTE acknowledgement") }
            cursor = end
        }
    }
    private func readChannel(_ channel: Channel) async throws -> Data {
        var output = Data()
        while true {
            let packet = try await receivePacket()
            if packet.command == ADBPacket.write {
                output.append(packet.payload)
                try await send(.init(command: ADBPacket.okay, argument0: channel.local, argument1: channel.remote, payload: Data()))
            } else if packet.command == ADBPacket.close {
                try await send(.init(command: ADBPacket.close, argument0: channel.local, argument1: channel.remote, payload: Data()))
                return output
            }
        }
    }
    private func send(_ packet: ADBPacket) async throws {
        guard let connection else { throw ADBClientError.notConnected }
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: packet.encoded, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: ADBClientError.connectionFailed(error.localizedDescription)) }
                else { continuation.resume() }
            })
        }
    }
    private func receivePacket() async throws -> ADBPacket {
        let header = try await receiveExactly(24), length = Int(header.littleEndianUInt32(at: 12))
        guard length <= maxPayload else { throw ADBClientError.invalidPacket("payload exceeds negotiated maximum") }
        return try ADBPacket.decode(header: header, payload: try await receiveExactly(length))
    }
    private func receiveExactly(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }; var result = Data()
        while result.count < count {
            guard let connection else { throw ADBClientError.notConnected }
            let remaining = count - result.count
            let part: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    if let error { continuation.resume(throwing: ADBClientError.connectionFailed(error.localizedDescription)) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: ADBClientError.connectionFailed(complete ? "连接已关闭" : "未收到数据")) }
                }
            }
            result.append(part)
        }
        return result
    }
    private func syncFrame(_ command: String, payload: Data) -> Data { var result = Data(command.utf8); result.appendLittleEndian(UInt32(payload.count)); result.append(payload); return result }
    private func syncFailure(_ data: Data) -> String { data.count > 8 ? String(decoding: data.dropFirst(8), as: UTF8.self) : "未知错误" }
    private func validatePackage(_ value: String) throws { guard !value.isEmpty, value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }) else { throw ADBClientError.commandFailed("包名无效") } }
    private func requireSuccess(_ output: String) throws { guard output.localizedCaseInsensitiveContains("success") else { throw ADBClientError.commandFailed(output) } }
}
