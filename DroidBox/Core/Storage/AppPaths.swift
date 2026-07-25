import Foundation

struct AppPaths: Sendable {
    let root: URL
    init(root: URL? = nil) throws {
        if let root { self.root = root }
        else { self.root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) }
        try createDirectories()
    }
    var library: URL { root.appending(path: "Library") }
    var libraryFile: URL { library.appending(path: "library.json") }
    var games: URL { root.appending(path: "Games") }
    var android: URL { root.appending(path: "Android") }
    var renpy: URL { root.appending(path: "RenPy") }
    var webRuntime: URL { root.appending(path: "WebRuntime") }
    var temporary: URL { root.appending(path: "Temp") }
    func game(_ id: UUID) -> URL { games.appending(path: id.uuidString) }
    private func createDirectories() throws {
        for url in [library, games, android, renpy, webRuntime, temporary] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

