import Foundation
import WebKit
import UniformTypeIdentifiers

final class GameSchemeHandler:NSObject,WKURLSchemeHandler,@unchecked Sendable {
    let gameID:UUID;let root:URL
    init(gameID:UUID,root:URL){self.gameID=gameID;self.root=root.standardizedFileURL}
    func webView(_ webView:WKWebView,start task:WKURLSchemeTask){
        guard let url=task.request.url,url.host==gameID.uuidString.lowercased() else{return fail(task,403,"禁止访问其他游戏")}
        let encoded=url.path.isEmpty ? "/index.html":url.path
        guard let decoded=encoded.removingPercentEncoding else{return fail(task,400,"无效路径")}
        let relative=decoded.trimmingCharacters(in:CharacterSet(charactersIn:"/"));guard SafeArchive.isSafe(relative) else{return fail(task,403,"不安全路径")}
        let file=root.appending(path:relative).standardizedFileURL;guard file.path.hasPrefix(root.path+"/"),FileManager.default.fileExists(atPath:file.path) else{return fail(task,404,"资源不存在")}
        do{
            let full=try Data(contentsOf:file,options:.mappedIfSafe);let total=full.count;var data=full,status=200,headers=["Accept-Ranges":"bytes","Cache-Control":"no-cache"]
            if let range=task.request.value(forHTTPHeaderField:"Range"),let parsed=parseRange(range,total:total){data=full.subdata(in:parsed);status=206;headers["Content-Range"]="bytes \(parsed.lowerBound)-\(parsed.upperBound-1)/\(total)"}
            let mime=UTType(filenameExtension:file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response=HTTPURLResponse(url:url,statusCode:status,httpVersion:"HTTP/1.1",headerFields:headers.merging(["Content-Type":mime,"Content-Length":"\(data.count)"]){$1})!
            task.didReceive(response);task.didReceive(data);task.didFinish()
        }catch{task.didFailWithError(error)}
    }
    func webView(_ webView:WKWebView,stop task:WKURLSchemeTask){}
    private func parseRange(_ value:String,total:Int)->Range<Int>?{guard value.hasPrefix("bytes="),let dash=value.firstIndex(of:"-") else{return nil};let start=Int(value[value.index(value.startIndex,offsetBy:6)..<dash]) ?? 0;let after=value.index(after:dash);let end=Int(value[after...]) ?? total-1;guard start>=0,start<=end,end<total else{return nil};return start..<(end+1)}
    private func fail(_ task:WKURLSchemeTask,_ status:Int,_ message:String){let error=NSError(domain:"DroidBox.Web",code:status,userInfo:[NSLocalizedDescriptionKey:message]);task.didFailWithError(error)}
}

