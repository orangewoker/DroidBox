import CoreGraphics
import Foundation

/// An immutable snapshot handed to the UI. `CGImage` is not formally `Sendable`, but a
/// finished image backed by immutable data is safe to read from any thread.
struct RFBFrame: @unchecked Sendable {
    let image: CGImage
    let width: Int
    let height: Int
    let generation: Int
}

/// Holds the guest screen as 32-bit BGRA and applies incoming rectangles in place.
/// Only the encodings DroidBox advertises are handled; anything else is rejected so a
/// mismatch surfaces as an error instead of a corrupted picture.
struct RFBFramebuffer {
    private(set) var width: Int
    private(set) var height: Int
    private(set) var generation = 0
    private var pixels: Data

    static let bytesPerPixel = 4

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Data(repeating: 0, count: width * height * Self.bytesPerPixel)
    }

    var byteCount: Int { width * height * Self.bytesPerPixel }

    mutating func resize(width newWidth: Int, height newHeight: Int) {
        guard newWidth > 0, newHeight > 0, newWidth != width || newHeight != height else { return }
        width = newWidth
        height = newHeight
        pixels = Data(repeating: 0, count: byteCount)
        generation += 1
    }

    /// Byte count the server will send for a rectangle, or nil when the rectangle is
    /// self-describing and must be read incrementally by the caller.
    static func rawPayloadLength(for rectangle: RFBRectangle) -> Int {
        rectangle.width * rectangle.height * bytesPerPixel
    }

    mutating func applyRaw(_ rectangle: RFBRectangle, payload: Data) throws {
        try validate(rectangle)
        guard payload.count == Self.rawPayloadLength(for: rectangle) else { throw RFBError.truncatedMessage }
        let stride = width * Self.bytesPerPixel, rowBytes = rectangle.width * Self.bytesPerPixel
        payload.withUnsafeBytes { source in
            pixels.withUnsafeMutableBytes { destination in
                for row in 0..<rectangle.height {
                    let from = row * rowBytes
                    let to = (rectangle.y + row) * stride + rectangle.x * Self.bytesPerPixel
                    destination.baseAddress!.advanced(by: to)
                        .copyMemory(from: source.baseAddress!.advanced(by: from), byteCount: rowBytes)
                }
            }
        }
        generation += 1
    }

    mutating func applyCopyRect(_ rectangle: RFBRectangle, sourceX: Int, sourceY: Int) throws {
        try validate(rectangle)
        try validate(RFBRectangle(x: sourceX, y: sourceY, width: rectangle.width, height: rectangle.height, encoding: rectangle.encoding))
        let stride = width * Self.bytesPerPixel, rowBytes = rectangle.width * Self.bytesPerPixel
        // Copy through a staging buffer so overlapping source and destination stay correct.
        var staging = Data(count: rectangle.height * rowBytes)
        pixels.withUnsafeBytes { source in
            staging.withUnsafeMutableBytes { destination in
                for row in 0..<rectangle.height {
                    let from = (sourceY + row) * stride + sourceX * Self.bytesPerPixel
                    destination.baseAddress!.advanced(by: row * rowBytes)
                        .copyMemory(from: source.baseAddress!.advanced(by: from), byteCount: rowBytes)
                }
            }
        }
        staging.withUnsafeBytes { source in
            pixels.withUnsafeMutableBytes { destination in
                for row in 0..<rectangle.height {
                    let to = (rectangle.y + row) * stride + rectangle.x * Self.bytesPerPixel
                    destination.baseAddress!.advanced(by: to)
                        .copyMemory(from: source.baseAddress!.advanced(by: row * rowBytes), byteCount: rowBytes)
                }
            }
        }
        generation += 1
    }

    func makeFrame() -> RFBFrame? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * Self.bytesPerPixel, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return RFBFrame(image: image, width: width, height: height, generation: generation)
    }

    private func validate(_ rectangle: RFBRectangle) throws {
        guard rectangle.x >= 0, rectangle.y >= 0, rectangle.width >= 0, rectangle.height >= 0,
              rectangle.x + rectangle.width <= width, rectangle.y + rectangle.height <= height else {
            throw RFBError.protocolViolation("矩形 \(rectangle.width)x\(rectangle.height)@\(rectangle.x),\(rectangle.y) 超出画面 \(width)x\(height)")
        }
    }
}
