import Foundation

enum RFBError: LocalizedError, Equatable, Sendable {
    case invalidPort
    case handshakeFailed(String)
    case unsupportedSecurity([UInt8])
    case authenticationRequired
    case authenticationFailed(String)
    case truncatedMessage
    case unsupportedEncoding(Int32)
    case protocolViolation(String)
    case disconnected(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort: "显示通道端口无效"
        case .handshakeFailed(let value): "VNC 握手失败：\(value)"
        case .unsupportedSecurity(let types): "Android 显示通道要求不支持的认证方式：\(types.map(String.init).joined(separator: ", "))"
        case .authenticationRequired: "Android 显示通道要求密码认证，当前运行时未提供凭据"
        case .authenticationFailed(let value): "显示通道认证被拒绝：\(value)"
        case .truncatedMessage: "显示通道数据不完整"
        case .unsupportedEncoding(let value): "显示通道使用了不支持的编码 \(value)"
        case .protocolViolation(let value): "显示通道协议错误：\(value)"
        case .disconnected(let value): "显示通道已断开：\(value)"
        }
    }
}

/// Cursor-based big-endian reader. RFB is defined entirely in network byte order.
struct RFBReader {
    private let data: Data
    private var cursor: Int

    init(_ data: Data) { self.data = data; cursor = data.startIndex }
    var remaining: Int { data.endIndex - cursor }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw RFBError.truncatedMessage }
        defer { cursor += 1 }
        return data[cursor]
    }
    mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw RFBError.truncatedMessage }
        defer { cursor += 2 }
        return UInt16(data[cursor]) << 8 | UInt16(data[cursor + 1])
    }
    mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw RFBError.truncatedMessage }
        defer { cursor += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(data[cursor + $1]) }
    }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw RFBError.truncatedMessage }
        defer { cursor += count }
        return Data(data[cursor..<cursor + count])
    }
    mutating func skip(_ count: Int) throws {
        guard count >= 0, remaining >= count else { throw RFBError.truncatedMessage }
        cursor += count
    }
}

struct RFBWriter {
    private(set) var data = Data()
    mutating func u8(_ value: UInt8) { data.append(value) }
    mutating func u16(_ value: UInt16) { data.append(UInt8(truncatingIfNeeded: value >> 8)); data.append(UInt8(truncatingIfNeeded: value)) }
    mutating func u32(_ value: UInt32) { for shift in stride(from: 24, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) } }
    mutating func i32(_ value: Int32) { u32(UInt32(bitPattern: value)) }
    mutating func pad(_ count: Int) { data.append(Data(repeating: 0, count: count)) }
    mutating func append(_ other: Data) { data.append(other) }
}

struct RFBPixelFormat: Equatable, Sendable {
    var bitsPerPixel: UInt8
    var depth: UInt8
    var bigEndian: Bool
    var trueColor: Bool
    var redMax: UInt16
    var greenMax: UInt16
    var blueMax: UInt16
    var redShift: UInt8
    var greenShift: UInt8
    var blueShift: UInt8

    /// Little-endian 32-bit XRGB, which lands in memory as B, G, R, X per pixel.
    /// Core Graphics consumes that directly as `noneSkipFirst | byteOrder32Little`.
    static let bgra32 = RFBPixelFormat(
        bitsPerPixel: 32, depth: 24, bigEndian: false, trueColor: true,
        redMax: 255, greenMax: 255, blueMax: 255,
        redShift: 16, greenShift: 8, blueShift: 0
    )

    var encoded: Data {
        var writer = RFBWriter()
        writer.u8(bitsPerPixel); writer.u8(depth); writer.u8(bigEndian ? 1 : 0); writer.u8(trueColor ? 1 : 0)
        writer.u16(redMax); writer.u16(greenMax); writer.u16(blueMax)
        writer.u8(redShift); writer.u8(greenShift); writer.u8(blueShift); writer.pad(3)
        return writer.data
    }

    static func decode(_ reader: inout RFBReader) throws -> RFBPixelFormat {
        let format = RFBPixelFormat(
            bitsPerPixel: try reader.u8(), depth: try reader.u8(),
            bigEndian: try reader.u8() != 0, trueColor: try reader.u8() != 0,
            redMax: try reader.u16(), greenMax: try reader.u16(), blueMax: try reader.u16(),
            redShift: try reader.u8(), greenShift: try reader.u8(), blueShift: try reader.u8()
        )
        try reader.skip(3)
        return format
    }
}

struct RFBRectangle: Sendable, Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let encoding: Int32
}

enum RFBEncoding: Int32, Sendable, CaseIterable {
    case raw = 0
    case copyRect = 1
    case desktopSize = -223
}

enum RFBSecurity: UInt8, Sendable {
    case invalid = 0
    case none = 1
    case vncAuthentication = 2
}

/// The RFB 3.8 handshake, expressed as pure functions so the sequence is testable
/// without a live server.
enum RFBHandshake {
    static let clientVersion = Data("RFB 003.008\n".utf8)
    static let serverInitHeaderLength = 24

    /// DroidBox always replies `RFB 003.008`, and only 3.7+ negotiates security as a list
    /// of offered types. RFB 3.3 sends a bare 4-byte type instead, so accepting it here
    /// would desync the rest of the handshake. QEMU speaks 3.8.
    static func parseVersion(_ data: Data) throws -> (major: Int, minor: Int) {
        guard data.count == 12, let text = String(data: data, encoding: .utf8), text.hasPrefix("RFB ") else {
            throw RFBError.handshakeFailed("服务器版本标识无效")
        }
        let parts = text.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1]) else {
            throw RFBError.handshakeFailed("无法解析版本 \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        guard major == 3, minor >= 7 else { throw RFBError.handshakeFailed("不支持 RFB \(major).\(minor)，需要 3.7 或更高") }
        return (major, minor)
    }

    /// DroidBox only accepts unauthenticated loopback sessions. A runtime that demands a
    /// password is reported rather than silently retried, matching the rest of the app.
    static func selectSecurity(from types: [UInt8]) throws -> UInt8 {
        guard !types.isEmpty else { throw RFBError.handshakeFailed("服务器未提供认证方式") }
        if types.contains(RFBSecurity.none.rawValue) { return RFBSecurity.none.rawValue }
        if types.contains(RFBSecurity.vncAuthentication.rawValue) { throw RFBError.authenticationRequired }
        throw RFBError.unsupportedSecurity(types)
    }

    static func parseServerInitHeader(_ data: Data) throws -> (width: Int, height: Int, format: RFBPixelFormat, nameLength: Int) {
        var reader = RFBReader(data)
        let width = Int(try reader.u16()), height = Int(try reader.u16())
        let format = try RFBPixelFormat.decode(&reader)
        let nameLength = Int(try reader.u32())
        guard width > 0, height > 0, width <= 16_384, height <= 16_384 else {
            throw RFBError.protocolViolation("画面尺寸 \(width)x\(height) 超出允许范围")
        }
        guard nameLength <= 4096 else { throw RFBError.protocolViolation("桌面名称过长") }
        return (width, height, format, nameLength)
    }
}

enum RFBClientMessage {
    private static let setPixelFormatType: UInt8 = 0
    private static let setEncodingsType: UInt8 = 2
    private static let updateRequestType: UInt8 = 3
    private static let keyEventType: UInt8 = 4
    private static let pointerEventType: UInt8 = 5

    static func clientInit(shared: Bool) -> Data { Data([shared ? 1 : 0]) }

    static func setPixelFormat(_ format: RFBPixelFormat) -> Data {
        var writer = RFBWriter()
        writer.u8(setPixelFormatType); writer.pad(3); writer.append(format.encoded)
        return writer.data
    }

    static func setEncodings(_ encodings: [Int32]) -> Data {
        var writer = RFBWriter()
        writer.u8(setEncodingsType); writer.pad(1); writer.u16(UInt16(encodings.count))
        encodings.forEach { writer.i32($0) }
        return writer.data
    }

    static func framebufferUpdateRequest(incremental: Bool, x: Int, y: Int, width: Int, height: Int) -> Data {
        var writer = RFBWriter()
        writer.u8(updateRequestType); writer.u8(incremental ? 1 : 0)
        writer.u16(UInt16(clamping: x)); writer.u16(UInt16(clamping: y))
        writer.u16(UInt16(clamping: width)); writer.u16(UInt16(clamping: height))
        return writer.data
    }

    static func pointerEvent(buttonMask: UInt8, x: Int, y: Int) -> Data {
        var writer = RFBWriter()
        writer.u8(pointerEventType); writer.u8(buttonMask)
        writer.u16(UInt16(clamping: x)); writer.u16(UInt16(clamping: y))
        return writer.data
    }

    static func keyEvent(down: Bool, keysym: UInt32) -> Data {
        var writer = RFBWriter()
        writer.u8(keyEventType); writer.u8(down ? 1 : 0); writer.pad(2); writer.u32(keysym)
        return writer.data
    }
}

/// X11 keysyms QEMU translates into Linux input codes that Android understands.
enum RFBKeysym {
    /// KEY_ESC, which the Android input stack maps to the Back button.
    static let escape: UInt32 = 0xff1b
    /// KEY_HOME on the guest keyboard layout.
    static let home: UInt32 = 0xff50
    static let enter: UInt32 = 0xff0d
    static let backspace: UInt32 = 0xff08
}
