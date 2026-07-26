import CoreGraphics
import Foundation
import Observation

/// Owns the RFB update loop and publishes frames to SwiftUI.
///
/// The loop is pull-based: request an update, wait for the server's rectangles, repeat.
/// QEMU coalesces changes between requests, so the guest sets the pace and a slow guest
/// simply produces fewer frames rather than backing up a queue.
@MainActor @Observable
final class VMDisplayController {
    private(set) var frame: RFBFrame?
    private(set) var isConnected = false
    private(set) var errorMessage: String?
    private(set) var desktopName = ""

    private let client = RFBClient()
    private var loop: Task<Void, Never>?

    var screenSize: CGSize {
        guard let frame else { return .zero }
        return CGSize(width: frame.width, height: frame.height)
    }

    func start(port: UInt16) {
        loop?.cancel()
        errorMessage = nil
        let client = self.client
        loop = Task { [weak self] in
            do {
                try await client.connect(port: port)
                let name = await client.desktopName
                let size = await client.screenSize
                self?.desktopName = name
                self?.isConnected = true
                await AppLogger.shared.log(.default, "VNC connected \(size.width)x\(size.height)")
                try await client.requestUpdate(incremental: false)
                while !Task.isCancelled {
                    if let frame = try await client.readMessage() { self?.frame = frame }
                    try await client.requestUpdate(incremental: true)
                }
            } catch is CancellationError {
                // Normal teardown when the player closes.
            } catch {
                self?.errorMessage = error.localizedDescription
                await AppLogger.shared.log(.error, "VNC loop stopped: \(error.localizedDescription)")
            }
            await client.disconnect()
            self?.isConnected = false
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        isConnected = false
        frame = nil
        let client = self.client
        Task { await client.disconnect() }
    }

    /// Maps a tap in view space to guest pixels and sends press followed by release.
    func tap(at point: CGPoint, in viewSize: CGSize) {
        guard let guest = guestPoint(for: point, in: viewSize) else { return }
        let client = self.client
        Task {
            try? await client.sendPointer(buttonMask: 1, x: guest.x, y: guest.y)
            try? await client.sendPointer(buttonMask: 0, x: guest.x, y: guest.y)
        }
    }

    func dragChanged(to point: CGPoint, in viewSize: CGSize) {
        guard let guest = guestPoint(for: point, in: viewSize) else { return }
        let client = self.client
        Task { try? await client.sendPointer(buttonMask: 1, x: guest.x, y: guest.y) }
    }

    func dragEnded(at point: CGPoint, in viewSize: CGSize) {
        guard let guest = guestPoint(for: point, in: viewSize) else { return }
        let client = self.client
        Task { try? await client.sendPointer(buttonMask: 0, x: guest.x, y: guest.y) }
    }

    func sendKey(_ keysym: UInt32) {
        let client = self.client
        Task { try? await client.sendKey(keysym) }
    }

    /// Inverts the aspect-preserving fit used by the display surface. Points in the
    /// letterbox margins have no guest pixel and are dropped.
    func guestPoint(for point: CGPoint, in viewSize: CGSize) -> (x: Int, y: Int)? {
        RFBTouchMapper.guestPoint(for: point, in: viewSize, screen: screenSize)
    }
}

/// The inverse of `scaledToFit`, kept separate from the controller so the geometry can be
/// verified without a live framebuffer.
enum RFBTouchMapper {
    static func guestPoint(for point: CGPoint, in viewSize: CGSize, screen: CGSize) -> (x: Int, y: Int)? {
        guard screen.width > 0, screen.height > 0, viewSize.width > 0, viewSize.height > 0 else { return nil }
        let scale = min(viewSize.width / screen.width, viewSize.height / screen.height)
        guard scale > 0 else { return nil }
        let drawn = CGSize(width: screen.width * scale, height: screen.height * scale)
        let origin = CGPoint(x: (viewSize.width - drawn.width) / 2, y: (viewSize.height - drawn.height) / 2)
        let local = CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
        guard local.x >= 0, local.y >= 0, local.x < screen.width, local.y < screen.height else { return nil }
        return (Int(local.x), Int(local.y))
    }
}
