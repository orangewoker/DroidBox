import Foundation

struct EngineDetection: Sendable { let engine: GameEngine; let confidence: Double; let scores: [GameEngine: Int] }

enum EngineDetector {
    static func detect(paths: [String]) -> EngineDetection {
        let lower=Set(paths.map{$0.lowercased()}), all=lower.joined(separator:"\n")
        var score: [GameEngine:Int] = [:]
        func add(_ engine: GameEngine, _ points: Int, when condition: Bool) { if condition { score[engine,default:0]+=points } }
        add(.renpy8,45,when:all.contains("assets/x-game/")); add(.renpy8,25,when:all.contains(".rpyc")); add(.renpy8,30,when:all.contains("librenpython.so")); add(.renpy7,35,when:all.contains("assets/game/")); add(.renpy7,20,when:all.contains("x-android.json"))
        add(.kirikiri, 65, when: paths.contains { $0.lowercased().hasSuffix(".xp3") })
        add(.kirikiri, 25, when: paths.contains { $0.lowercased().hasSuffix(".tjs") })
        add(.rpgMakerMV,45,when:lower.contains("assets/www/js/rpg_core.js")); add(.rpgMakerMZ,50,when:lower.contains("assets/www/js/rmmz_core.js")); add(.rpgMakerMV,25,when:lower.contains("assets/www/index.html")); add(.rpgMakerMZ,20,when:lower.contains("assets/www/data/system.json"))
        add(.unity,50,when:all.contains("libunity.so")); add(.unity,30,when:all.contains("assets/bin/data/")); add(.unity,20,when:all.contains("global-metadata.dat"))
        add(.godot,60,when:all.contains("libgodot_android.so")); add(.godot,25,when:all.contains(".pck")); add(.libgdx,60,when:all.contains("libgdx.so")); add(.libgdx,25,when:all.contains("com/badlogic/gdx"))
        let best=score.max{$0.value<$1.value}; return EngineDetection(engine:best?.key ?? .android,confidence:min(1,Double(best?.value ?? 35)/100),scores:score)
    }
}
