import Foundation

enum QCOW2OverlayBuilder {
    private static let magic: UInt32 = 0x514649fb

    static func create(backingFile: URL, overlay: URL) throws {
        let source = try FileHandle(forReadingFrom: backingFile); defer { try? source.close() }
        let baseHeader = try source.read(upToCount: 104) ?? Data()
        guard baseHeader.count >= 32, baseHeader.bigEndianUInt32(at: 0) == magic else { throw DroidBoxError.runtimeCorrupted }
        let clusterBits = Int(baseHeader.bigEndianUInt32(at: 20)), virtualSize = baseHeader.bigEndianUInt64(at: 24)
        guard clusterBits >= 9, clusterBits <= 21, virtualSize > 0 else { throw DroidBoxError.runtimeCorrupted }
        let clusterSize = 1 << clusterBits, backing = Data(backingFile.path.utf8)
        guard 104 + backing.count < clusterSize else { throw DroidBoxError.runtimeCorrupted }
        let l2Coverage = UInt64(clusterSize) * UInt64(clusterSize / 8)
        let l1Size = UInt32((virtualSize + l2Coverage - 1) / l2Coverage)
        guard UInt64(l1Size) * 8 <= UInt64(clusterSize) else { throw DroidBoxError.runtimeCorrupted }

        var output = Data(repeating: 0, count: clusterSize * 4)
        output.setBigEndian(magic, at: 0); output.setBigEndian(UInt32(3), at: 4)
        output.setBigEndian(UInt64(104), at: 8); output.setBigEndian(UInt32(backing.count), at: 16)
        output.setBigEndian(UInt32(clusterBits), at: 20); output.setBigEndian(virtualSize, at: 24)
        output.setBigEndian(UInt32(0), at: 32); output.setBigEndian(l1Size, at: 36); output.setBigEndian(UInt64(clusterSize * 3), at: 40)
        output.setBigEndian(UInt64(clusterSize), at: 48); output.setBigEndian(UInt32(1), at: 56)
        output.setBigEndian(UInt32(0), at: 60); output.setBigEndian(UInt64(0), at: 64)
        output.setBigEndian(UInt64(0), at: 72); output.setBigEndian(UInt64(0), at: 80); output.setBigEndian(UInt64(0), at: 88)
        output.setBigEndian(UInt32(4), at: 96); output.setBigEndian(UInt32(104), at: 100)
        output.replaceSubrange(104..<104 + backing.count, with: backing)
        output.setBigEndian(UInt64(clusterSize * 2), at: clusterSize)
        for cluster in 0..<4 { output.setBigEndian(UInt16(1), at: clusterSize * 2 + cluster * 2) }
        try FileManager.default.createDirectory(at: overlay.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: overlay, options: .atomic)
    }
}

private extension Data {
    func bigEndianUInt32(at offset: Int) -> UInt32 { guard offset + 4 <= count else { return 0 }; return UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16 | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3]) }
    func bigEndianUInt64(at offset: Int) -> UInt64 { UInt64(bigEndianUInt32(at: offset)) << 32 | UInt64(bigEndianUInt32(at: offset + 4)) }
    mutating func setBigEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        let bytes = Swift.withUnsafeBytes(of: value.bigEndian) { Data($0) }; replaceSubrange(offset..<offset + bytes.count, with: bytes)
    }
}

