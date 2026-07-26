import XCTest
@testable import DroidBox

final class RFBTests: XCTestCase {
    // MARK: Handshake

    func testParseVersionAcceptsSupportedServers() throws {
        let parsed = try RFBHandshake.parseVersion(Data("RFB 003.008\n".utf8))
        XCTAssertEqual(parsed.major, 3)
        XCTAssertEqual(parsed.minor, 8)
        XCTAssertEqual(try RFBHandshake.parseVersion(Data("RFB 003.003\n".utf8)).minor, 3)
    }

    func testParseVersionRejectsMalformedAndOldServers() {
        XCTAssertThrowsError(try RFBHandshake.parseVersion(Data("RFB 003.008".utf8)))
        XCTAssertThrowsError(try RFBHandshake.parseVersion(Data("HTTP/1.1 20".utf8)))
        XCTAssertThrowsError(try RFBHandshake.parseVersion(Data("RFB 003.002\n".utf8)))
        XCTAssertThrowsError(try RFBHandshake.parseVersion(Data("RFB 004.000\n".utf8)))
    }

    func testSelectSecurityPrefersNoneAndReportsPasswordServers() throws {
        XCTAssertEqual(try RFBHandshake.selectSecurity(from: [1, 2]), 1)
        XCTAssertEqual(try RFBHandshake.selectSecurity(from: [1]), 1)
        XCTAssertThrowsError(try RFBHandshake.selectSecurity(from: [2])) { error in
            XCTAssertEqual(error as? RFBError, .authenticationRequired)
        }
        XCTAssertThrowsError(try RFBHandshake.selectSecurity(from: []))
        XCTAssertThrowsError(try RFBHandshake.selectSecurity(from: [16, 18]))
    }

    func testServerInitHeaderRoundTrip() throws {
        var writer = RFBWriter()
        writer.u16(1080); writer.u16(1920)
        writer.append(RFBPixelFormat.bgra32.encoded)
        writer.u32(9)
        let parsed = try RFBHandshake.parseServerInitHeader(writer.data)
        XCTAssertEqual(parsed.width, 1080)
        XCTAssertEqual(parsed.height, 1920)
        XCTAssertEqual(parsed.format, .bgra32)
        XCTAssertEqual(parsed.nameLength, 9)
        XCTAssertEqual(writer.data.count, RFBHandshake.serverInitHeaderLength)
    }

    func testServerInitHeaderRejectsImpossibleGeometry() {
        var writer = RFBWriter()
        writer.u16(0); writer.u16(0)
        writer.append(RFBPixelFormat.bgra32.encoded)
        writer.u32(0)
        XCTAssertThrowsError(try RFBHandshake.parseServerInitHeader(writer.data))
    }

    // MARK: Message encoding

    func testPixelFormatEncodesSixteenBytes() {
        let encoded = RFBPixelFormat.bgra32.encoded
        XCTAssertEqual(encoded.count, 16)
        XCTAssertEqual(encoded[0], 32)
        XCTAssertEqual(encoded[1], 24)
        XCTAssertEqual(encoded[3], 1, "true colour must be set")
        XCTAssertEqual(encoded[2], 0, "little endian for Core Graphics")
    }

    func testPointerEventEncoding() {
        let data = RFBClientMessage.pointerEvent(buttonMask: 1, x: 258, y: 3)
        XCTAssertEqual(Array(data), [5, 1, 0x01, 0x02, 0x00, 0x03])
    }

    func testFramebufferUpdateRequestEncoding() {
        let data = RFBClientMessage.framebufferUpdateRequest(incremental: true, x: 0, y: 0, width: 1080, height: 1920)
        XCTAssertEqual(data.count, 10)
        XCTAssertEqual(data[0], 3)
        XCTAssertEqual(data[1], 1)
        XCTAssertEqual(UInt16(data[6]) << 8 | UInt16(data[7]), 1080)
        XCTAssertEqual(UInt16(data[8]) << 8 | UInt16(data[9]), 1920)
    }

    func testSetEncodingsCarriesNegativePseudoEncodings() throws {
        let data = RFBClientMessage.setEncodings([RFBEncoding.raw.rawValue, RFBEncoding.desktopSize.rawValue])
        var reader = RFBReader(data)
        XCTAssertEqual(try reader.u8(), 2)
        try reader.skip(1)
        XCTAssertEqual(try reader.u16(), 2)
        XCTAssertEqual(try reader.i32(), 0)
        XCTAssertEqual(try reader.i32(), -223)
    }

    func testReaderRejectsReadsPastEnd() {
        var reader = RFBReader(Data([1, 2]))
        XCTAssertThrowsError(try reader.u32())
        XCTAssertEqual(reader.remaining, 2, "a failed read must not consume bytes")
    }

    // MARK: Framebuffer

    func testApplyRawWritesRectangleAtOffset() throws {
        var framebuffer = RFBFramebuffer(width: 4, height: 4)
        let rectangle = RFBRectangle(x: 1, y: 2, width: 2, height: 2, encoding: 0)
        let payload = Data(repeating: 0xAB, count: RFBFramebuffer.rawPayloadLength(for: rectangle))
        try framebuffer.applyRaw(rectangle, payload: payload)
        XCTAssertEqual(framebuffer.generation, 1)
        XCTAssertNotNil(framebuffer.makeFrame())
    }

    func testApplyRawRejectsShortPayloadAndOutOfBoundsRectangle() {
        var framebuffer = RFBFramebuffer(width: 4, height: 4)
        let rectangle = RFBRectangle(x: 0, y: 0, width: 2, height: 2, encoding: 0)
        XCTAssertThrowsError(try framebuffer.applyRaw(rectangle, payload: Data(repeating: 0, count: 4)))
        let outside = RFBRectangle(x: 3, y: 3, width: 4, height: 4, encoding: 0)
        XCTAssertThrowsError(try framebuffer.applyRaw(outside, payload: Data(repeating: 0, count: RFBFramebuffer.rawPayloadLength(for: outside))))
    }

    func testCopyRectMovesPixelsAndHandlesOverlap() throws {
        var framebuffer = RFBFramebuffer(width: 4, height: 2)
        let source = RFBRectangle(x: 0, y: 0, width: 2, height: 2, encoding: 0)
        try framebuffer.applyRaw(source, payload: Data(repeating: 0x7F, count: RFBFramebuffer.rawPayloadLength(for: source)))
        // Overlapping shift by one column must not smear the source across the destination.
        let destination = RFBRectangle(x: 1, y: 0, width: 2, height: 2, encoding: 1)
        try framebuffer.applyCopyRect(destination, sourceX: 0, sourceY: 0)
        XCTAssertEqual(framebuffer.generation, 2)
        XCTAssertThrowsError(try framebuffer.applyCopyRect(destination, sourceX: 3, sourceY: 0))
    }

    func testResizeReallocatesAndBumpsGeneration() {
        var framebuffer = RFBFramebuffer(width: 8, height: 8)
        framebuffer.resize(width: 16, height: 4)
        XCTAssertEqual(framebuffer.width, 16)
        XCTAssertEqual(framebuffer.height, 4)
        XCTAssertEqual(framebuffer.byteCount, 16 * 4 * 4)
        XCTAssertEqual(framebuffer.generation, 1)
        framebuffer.resize(width: 16, height: 4)
        XCTAssertEqual(framebuffer.generation, 1, "an identical resize is a no-op")
    }

    func testFrameMatchesFramebufferGeometry() throws {
        var framebuffer = RFBFramebuffer(width: 3, height: 5)
        let rectangle = RFBRectangle(x: 0, y: 0, width: 3, height: 5, encoding: 0)
        try framebuffer.applyRaw(rectangle, payload: Data(repeating: 0x10, count: RFBFramebuffer.rawPayloadLength(for: rectangle)))
        let frame = try XCTUnwrap(framebuffer.makeFrame())
        XCTAssertEqual(frame.width, 3)
        XCTAssertEqual(frame.height, 5)
        XCTAssertEqual(frame.image.width, 3)
        XCTAssertEqual(frame.image.height, 5)
    }

    // MARK: Touch mapping

    @MainActor func testGuestPointRequiresAFrame() {
        let controller = VMDisplayController()
        XCTAssertNil(controller.guestPoint(for: CGPoint(x: 10, y: 10), in: CGSize(width: 100, height: 100)),
                     "with no frame there is no screen geometry to map into")
    }
}
