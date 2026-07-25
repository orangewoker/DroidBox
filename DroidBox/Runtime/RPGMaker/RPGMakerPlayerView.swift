import SwiftUI
import WebKit

struct RPGMakerPlayerView: UIViewRepresentable {
    let game: GameRecord

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(
            GameSchemeHandler(gameID: game.id, root: URL(fileURLWithPath: game.installedContentPath)),
            forURLScheme: "droidbox-game"
        )
        let bridge = """
        (()=>{const unlock=()=>{document.querySelectorAll('audio,video').forEach(x=>{const p=x.play();if(p)p.then(()=>x.pause()).catch(()=>{})});window.removeEventListener('touchstart',unlock)};window.addEventListener('touchstart',unlock,{once:true});window.DroidBox={exit:()=>webkit.messageHandlers.droidbox.postMessage({type:'exit'}),haptic:()=>webkit.messageHandlers.droidbox.postMessage({type:'haptic'}),safeArea:()=>({top:0,left:0,right:0,bottom:0})};window.addEventListener('error',e=>webkit.messageHandlers.droidbox.postMessage({type:'error',message:e.message}));})();
        """
        let script = WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(context.coordinator, name: "droidbox")

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.contentInsetAdjustmentBehavior = .never
        let gameURL = URL(string: "droidbox-game://\(game.id.uuidString.lowercased())/index.html")!
        view.load(URLRequest(url: gameURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], body["type"] as? String == "haptic" else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
