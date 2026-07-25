import Foundation
import OSLog

actor AppLogger {
    static let shared = AppLogger()
    private let system = Logger(subsystem: "com.droidbox.app", category: "DroidBox")
    private var fileURL: URL?

    func configure(paths: AppPaths) {
        fileURL = paths.root.appending(path: "droidbox.log")
    }
    func log(_ level: OSLogType = .default, _ message: String) {
        system.log(level: level, "\(message, privacy: .public)")
        guard let fileURL else { return }
        let clean = message.replacingOccurrences(of: NSHomeDirectory(), with: "<HOME>")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(clean)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: fileURL) { try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close() }
            else { try? data.write(to: fileURL, options: .atomic) }
        }
        rotateIfNeeded()
    }
    private func rotateIfNeeded() {
        guard let fileURL, let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize), size > 2_000_000 else { return }
        let backup = fileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: backup); try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}

