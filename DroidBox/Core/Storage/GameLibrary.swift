import Foundation
import Observation

@MainActor @Observable
final class GameLibrary {
    private(set) var games: [GameRecord] = []
    private(set) var lastError: String?
    let paths: AppPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(paths: AppPaths) {
        self.paths = paths
        encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func add(_ game: GameRecord) throws { games.append(game); try save() }
    func update(_ game: GameRecord) throws {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game; try save()
    }
    func remove(_ game: GameRecord) throws {
        games.removeAll { $0.id == game.id }; try save()
        try? FileManager.default.removeItem(at: paths.game(game.id))
    }

    private func load() {
        let file = paths.libraryFile, backup = file.appendingPathExtension("bak")
        for candidate in [file, backup] where FileManager.default.fileExists(atPath: candidate.path) {
            do { games = try decoder.decode([GameRecord].self, from: Data(contentsOf: candidate)); return }
            catch { lastError = "游戏库恢复失败：\(error.localizedDescription)" }
        }
    }

    private func save() throws {
        let data = try encoder.encode(games), file = paths.libraryFile
        let temporary = file.appendingPathExtension("tmp"), backup = file.appendingPathExtension("bak")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.copyItem(at: file, to: backup); try FileManager.default.removeItem(at: file) }
        try FileManager.default.moveItem(at: temporary, to: file)
    }
}

