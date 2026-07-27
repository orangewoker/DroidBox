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
    var importDirectory: URL { root.appending(path: "Import") }
    func game(_ id: UUID) -> URL { games.appending(path: id.uuidString) }
    private func createDirectories() throws {
        for url in [library, games, android, renpy, webRuntime, temporary, importDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let instructions = importDirectory.appending(path: "把APK或ZIP放到这里.txt")
        if !FileManager.default.fileExists(atPath: instructions.path) {
            try """
            DroidBox 本地导入目录

            1. 把 .apk 或 .zip 文件放进本目录。
            2. 回到 DroidBox，点击工具栏菜单里的“扫描 Import 目录”。
            3. 导入开始、完成或失败都会在 DroidBox 内显示明确提示。
            """.write(to: instructions, atomically: true, encoding: .utf8)
        }
    }
}
