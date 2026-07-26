import Foundation

/// Minimal RFB 3.8 client for the loopback VNC server QEMU exposes via `-vnc`.
///
/// Only Raw and CopyRect are advertised. Both are mandatory for every RFB server, so the
/// guest always has a working path, and neither needs a decompressor inside the app.
actor RFBClient {
    private let stream = ByteStream(label: "com.droidbox.rfb")
    private var framebuffer = RFBFramebuffer(width: 0, height: 0)
    private var connected = false
    private(set) var desktopName = ""

    private static let framebufferUpdate: UInt8 = 0
    private static let setColorMapEntries: UInt8 = 1
    private static let bell: UInt8 = 2
    private static let serverCutText: UInt8 = 3

    var screenSize: (width: Int, height: Int) { (framebuffer.width, framebuffer.height) }
    var isConnected: Bool { connected }

    func connect(host: String = "127.0.0.1", port: UInt16, timeout: Duration = .seconds(5)) async throws {
        try await stream.connect(host: host, port: port, timeout: timeout)
        do { try await handshake() } catch { await stream.close(); connected = false; throw error }
        connected = true
    }

    func disconnect() async {
        connected = false
        await stream.close()
    }

    private func handshake() async throws {
        let version = try await stream.read(12)
        _ = try RFBHandshake.parseVersion(version)
        try await stream.write(RFBHandshake.clientVersion)

        let count = Int(try await stream.read(1)[0])
        if count == 0 {
            let reason = try await readFailureReason()
            throw RFBError.handshakeFailed(reason)
        }
        let offered = Array(try await stream.read(count))
        let chosen = try RFBHandshake.selectSecurity(from: offered)
        try await stream.write(Data([chosen]))

        // RFB 3.8 always sends SecurityResult, even for the None type.
        guard beU32(try await stream.read(4)) == 0 else {
            throw RFBError.authenticationFailed(try await readFailureReason())
        }

        try await stream.write(RFBClientMessage.clientInit(shared: true))
        let header = try await stream.read(RFBHandshake.serverInitHeaderLength)
        let parsed = try RFBHandshake.parseServerInitHeader(header)
        if parsed.nameLength > 0 {
            desktopName = String(decoding: try await stream.read(parsed.nameLength), as: UTF8.self)
        }
        framebuffer = RFBFramebuffer(width: parsed.width, height: parsed.height)

        try await stream.write(RFBClientMessage.setPixelFormat(.bgra32))
        try await stream.write(RFBClientMessage.setEncodings([
            RFBEncoding.copyRect.rawValue, RFBEncoding.raw.rawValue, RFBEncoding.desktopSize.rawValue,
        ]))
    }

    func requestUpdate(incremental: Bool) async throws {
        guard connected else { throw RFBError.disconnected("显示通道未连接") }
        try await stream.write(RFBClientMessage.framebufferUpdateRequest(
            incremental: incremental, x: 0, y: 0,
            width: framebuffer.width, height: framebuffer.height
        ))
    }

    /// Reads one server message. Returns a frame when the framebuffer changed, and nil for
    /// messages that carry no pixels (bell, clipboard, colour map).
    func readMessage() async throws -> RFBFrame? {
        guard connected else { throw RFBError.disconnected("显示通道未连接") }
        let type = try await stream.read(1)[0]
        switch type {
        case Self.framebufferUpdate:
            return try await readFramebufferUpdate()
        case Self.setColorMapEntries:
            _ = try await stream.read(3)
            let count = Int(beU16(try await stream.read(2)))
            _ = try await stream.read(count * 6)
            return nil
        case Self.bell:
            return nil
        case Self.serverCutText:
            _ = try await stream.read(3)
            let length = Int(beU32(try await stream.read(4)))
            guard length <= 1 << 20 else { throw RFBError.protocolViolation("剪贴板数据过大") }
            _ = try await stream.read(length)
            return nil
        default:
            throw RFBError.protocolViolation("未知服务器消息类型 \(type)")
        }
    }

    private func readFramebufferUpdate() async throws -> RFBFrame? {
        _ = try await stream.read(1)
        let rectangles = Int(beU16(try await stream.read(2)))
        guard rectangles <= 4096 else { throw RFBError.protocolViolation("矩形数量异常：\(rectangles)") }
        var resized = false
        for _ in 0..<rectangles {
            let header = try await stream.read(12)
            var reader = RFBReader(header)
            let rectangle = RFBRectangle(
                x: Int(try reader.u16()), y: Int(try reader.u16()),
                width: Int(try reader.u16()), height: Int(try reader.u16()),
                encoding: try reader.i32()
            )
            switch rectangle.encoding {
            case RFBEncoding.raw.rawValue:
                let payload = try await stream.read(RFBFramebuffer.rawPayloadLength(for: rectangle))
                try framebuffer.applyRaw(rectangle, payload: payload)
            case RFBEncoding.copyRect.rawValue:
                let source = try await stream.read(4)
                try framebuffer.applyCopyRect(rectangle, sourceX: Int(beU16(source.prefix(2))), sourceY: Int(beU16(source.suffix(2))))
            case RFBEncoding.desktopSize.rawValue:
                framebuffer.resize(width: rectangle.width, height: rectangle.height)
                resized = true
            default:
                throw RFBError.unsupportedEncoding(rectangle.encoding)
            }
        }
        // A resize invalidates every pixel, so ask for a full repaint rather than a delta.
        if resized { try await requestUpdate(incremental: false) }
        return framebuffer.makeFrame()
    }

    func sendPointer(buttonMask: UInt8, x: Int, y: Int) async throws {
        guard connected else { return }
        let clampedX = min(max(x, 0), max(framebuffer.width - 1, 0))
        let clampedY = min(max(y, 0), max(framebuffer.height - 1, 0))
        try await stream.write(RFBClientMessage.pointerEvent(buttonMask: buttonMask, x: clampedX, y: clampedY))
    }

    func sendKey(_ keysym: UInt32) async throws {
        guard connected else { return }
        try await stream.write(RFBClientMessage.keyEvent(down: true, keysym: keysym))
        try await stream.write(RFBClientMessage.keyEvent(down: false, keysym: keysym))
    }

    private func readFailureReason() async throws -> String {
        let length = Int(beU32(try await stream.read(4)))
        guard length > 0, length <= 4096 else { return "服务器未提供原因" }
        return String(decoding: try await stream.read(length), as: UTF8.self)
    }

    private func beU16(_ data: Data) -> UInt16 { data.reduce(UInt16(0)) { $0 << 8 | UInt16($1) } }
    private func beU32(_ data: Data) -> UInt32 { data.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
}
