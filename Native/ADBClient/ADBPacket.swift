import Foundation

struct ADBPacket: Sendable, Equatable {
    let command: UInt32
    let argument0: UInt32
    let argument1: UInt32
    let payload: Data

    static let connect = fourCC("CNXN"), authentication = fourCC("AUTH"), open = fourCC("OPEN")
    static let okay = fourCC("OKAY"), close = fourCC("CLSE"), write = fourCC("WRTE")

    var encoded: Data {
        var result = Data()
        result.appendLittleEndian(command); result.appendLittleEndian(argument0); result.appendLittleEndian(argument1)
        result.appendLittleEndian(UInt32(payload.count)); result.appendLittleEndian(payload.reduce(UInt32(0)) { $0 &+ UInt32($1) })
        result.appendLittleEndian(command ^ UInt32.max); result.append(payload)
        return result
    }

    static func decode(header: Data, payload: Data) throws -> ADBPacket {
        guard header.count == 24 else { throw ADBClientError.invalidPacket("ADB header length") }
        let command = header.littleEndianUInt32(at: 0), argument0 = header.littleEndianUInt32(at: 4), argument1 = header.littleEndianUInt32(at: 8)
        let length = Int(header.littleEndianUInt32(at: 12)), checksum = header.littleEndianUInt32(at: 16), magic = header.littleEndianUInt32(at: 20)
        guard length == payload.count, magic == command ^ UInt32.max else { throw ADBClientError.invalidPacket("ADB header validation") }
        guard payload.reduce(UInt32(0), { $0 &+ UInt32($1) }) == checksum else { throw ADBClientError.invalidPacket("ADB checksum") }
        return ADBPacket(command: command, argument0: argument0, argument1: argument1, payload: payload)
    }

    private static func fourCC(_ value: String) -> UInt32 {
        value.utf8.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}

