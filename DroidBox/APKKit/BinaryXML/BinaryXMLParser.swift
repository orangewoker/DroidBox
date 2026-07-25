import Foundation
import FoundationXML

struct ManifestInfo: Sendable {
    var packageName: String?
    var versionName: String?
    var versionCode: Int64?
    var label: String?
    var iconResource: String?
    var launcherActivity: String?
    var orientation: GameOrientation = .automatic
    var minSDK: Int?
    var targetSDK: Int?
    var permissions: [String] = []
    var features: [String] = []
}

enum BinaryXMLParser {
    private static let stringPool: UInt16 = 0x0001, startElement: UInt16 = 0x0102

    static func parse(_ data: Data) throws -> ManifestInfo {
        if let prefix = String(data: data.prefix(100), encoding: .utf8), prefix.contains("<manifest") { return try parseText(data) }
        let reader = DataReader(data); guard reader.u16(0) == 0x0003 else { throw DroidBoxError.invalidArchive }
        var strings: [String] = [], info = ManifestInfo(), offset = Int(reader.u16(2))
        while offset + 8 <= data.count {
            let type = reader.u16(offset), header = Int(reader.u16(offset + 2)), size = Int(reader.u32(offset + 4))
            guard header >= 8, size >= header, offset + size <= data.count else { throw DroidBoxError.invalidArchive }
            if type == stringPool { strings = try readStringPool(reader, offset: offset) }
            else if type == startElement { parseElement(reader, offset: offset, strings: strings, info: &info) }
            offset += size
        }
        guard info.packageName != nil else { throw DroidBoxError.invalidArchive }; return info
    }

    private static func readStringPool(_ r: DataReader, offset: Int) throws -> [String] {
        let count = Int(r.u32(offset + 8)), flags = r.u32(offset + 16), start = Int(r.u32(offset + 20)), header = Int(r.u16(offset + 2))
        guard count < 100_000 else { throw DroidBoxError.invalidArchive }
        return (0..<count).map { index in
            let position = offset + start + Int(r.u32(offset + header + index * 4))
            return flags & 0x100 != 0 ? r.utf8String(position) : r.utf16String(position)
        }
    }

    private static func parseElement(_ r: DataReader, offset: Int, strings: [String], info: inout ManifestInfo) {
        let name = string(strings, Int(r.u32(offset + 20))), attributeStart = Int(r.u16(offset + 24)), attributeSize = Int(r.u16(offset + 26)), count = Int(r.u16(offset + 28))
        var attrs: [String: String] = [:]
        for i in 0..<count {
            let at = offset + 16 + attributeStart + i * attributeSize
            let key = string(strings, Int(r.u32(at + 4))), raw = r.u32(at + 8), type = r.u8(at + 15), value = r.u32(at + 16)
            let decoded: String
            if raw != UInt32.max { decoded = string(strings, Int(raw)) }
            else if type == 0x03 { decoded = string(strings, Int(value)) }
            else if type == 0x10 || type == 0x11 { decoded = String(value) }
            else if type == 0x12 { decoded = value == 0 ? "false" : "true" }
            else if type == 0x01 { decoded = String(format: "@0x%08x", value) }
            else { decoded = String(value) }
            attrs[key] = decoded
        }
        switch name {
        case "manifest": info.packageName = attrs["package"]; info.versionName = attrs["versionName"]; info.versionCode = attrs["versionCode"].flatMap(Int64.init)
        case "uses-sdk": info.minSDK = attrs["minSdkVersion"].flatMap(Int.init); info.targetSDK = attrs["targetSdkVersion"].flatMap(Int.init)
        case "uses-permission": if let value = attrs["name"] { info.permissions.append(value) }
        case "uses-feature": if let value = attrs["name"] { info.features.append(value) }
        case "application": info.label = attrs["label"]; info.iconResource = attrs["icon"]
        case "activity", "activity-alias":
            if info.launcherActivity == nil, let activity = attrs["name"] { info.launcherActivity = activity }
            if let value = attrs["screenOrientation"] { info.orientation = value.contains("landscape") ? .landscape : value.contains("portrait") ? .portrait : .automatic }
        default: break
        }
    }

    private static func parseText(_ data: Data) throws -> ManifestInfo {
        final class Delegate: NSObject, XMLParserDelegate {
            var info = ManifestInfo()
            func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
                func value(_ key: String) -> String? { attributes[key] ?? attributes["android:\(key)"] }
                if element == "manifest" { info.packageName=value("package"); info.versionName=value("versionName"); info.versionCode=value("versionCode").flatMap(Int64.init) }
                if element == "application" { info.label=value("label"); info.iconResource=value("icon") }
                if element == "uses-permission", let v=value("name") { info.permissions.append(v) }
                if element == "uses-feature", let v=value("name") { info.features.append(v) }
            }
        }
        let delegate=Delegate(), parser=XMLParser(data:data); parser.delegate=delegate
        guard parser.parse() else { throw DroidBoxError.invalidArchive }; return delegate.info
    }
    private static func string(_ strings: [String], _ index: Int) -> String { index >= 0 && index < strings.count ? strings[index] : "" }
}

private struct DataReader {
    let data: Data
    func u8(_ o: Int) -> UInt8 { o < data.count ? data[o] : 0 }
    func u16(_ o: Int) -> UInt16 { UInt16(u8(o)) | UInt16(u8(o+1)) << 8 }
    func u32(_ o: Int) -> UInt32 { UInt32(u16(o)) | UInt32(u16(o+2)) << 16 }
    func utf8String(_ offset: Int) -> String {
        var p=offset; _=length8(&p); let byteLength=length8(&p); guard p+byteLength<=data.count else{return ""}; return String(data:data[p..<p+byteLength],encoding:.utf8) ?? ""
    }
    func utf16String(_ offset: Int) -> String {
        var p=offset; let length=length16(&p); guard p+length*2<=data.count else{return ""}; return String(data:data[p..<p+length*2],encoding:.utf16LittleEndian) ?? ""
    }
    private func length8(_ p: inout Int) -> Int { let first=Int(u8(p));p+=1;if first&0x80 != 0{let second=Int(u8(p));p+=1;return((first&0x7f)<<8)|second};return first }
    private func length16(_ p: inout Int) -> Int { let first=Int(u16(p));p+=2;if first&0x8000 != 0{let second=Int(u16(p));p+=2;return((first&0x7fff)<<16)|second};return first }
}
