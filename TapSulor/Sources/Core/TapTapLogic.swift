import Foundation

/// TapTap 相关的纯逻辑（无 UIKit / WebKit 依赖）。
/// 规则对齐桌面版 main.js（probeDeveloperId、extractMeId、normalizeStudio、extractDeveloperIdFromUrl），
/// 会话分类对齐 assets/account-state.js 的 classifySessionIdentity。
enum TapTapLogic {
    static let origin = "https://developer.taptap.cn"
    static let mePath = "/api/user/v1/me"
    static let developerListPath = "/api/developer/v1/list"

    /// 解析接口时用到的汇总结果
    struct ProbedIdentity: Equatable {
        var meDeveloperId: String?
        var nickname: String
        var avatar: String
        var studios: [StudioRecord]?
    }

    // MARK: - 基础取值

    static func safeString(_ value: Any?) -> String {
        switch value {
        case let text as String:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        case let object as [String: Any]:
            for key in ["url", "src", "uri"] {
                if let text = object[key] as? String {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return ""
        default:
            return ""
        }
    }

    static func firstNonBlank(_ object: [String: Any]?, _ keys: [String]) -> String {
        guard let object = object else { return "" }
        for key in keys {
            let value = safeString(object[key])
            if !value.isEmpty { return value }
        }
        return ""
    }

    static func normalizeURL(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("data:") { return text }
        if text.hasPrefix("//") { return "https:" + text }
        return text
    }

    /// 与桌面版 normDeveloperId 一致：纯数字，或 "123.0" 这类写法。
    static func normalizeDeveloperId(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(".0") { trimmed.removeLast(2) }
            return isDigits(trimmed) ? trimmed : nil
        case let number as NSNumber:
            let double = number.doubleValue
            guard double.rounded() == double, double >= 0, double < 1e18 else { return nil }
            return String(Int64(double))
        default:
            return nil
        }
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    static func isSuccess(_ response: APIResponse?) -> Bool {
        guard let response = response else { return false }
        return (200..<300).contains(response.status)
    }

    // MARK: - 接口解析

    /// /api/user/v1/me：data.developer_id > data.developerId > data.developer.id
    static func developerId(fromMe json: [String: Any]?) -> String? {
        guard let data = json?["data"] as? [String: Any] else { return nil }
        if let id = normalizeDeveloperId(data["developer_id"]) { return id }
        if let id = normalizeDeveloperId(data["developerId"]) { return id }
        if let developer = data["developer"] as? [String: Any], let id = normalizeDeveloperId(developer["id"]) {
            return id
        }
        return nil
    }

    /// /api/developer/v1/list：data.list[] 中的开发者 ID（去重，保持顺序）
    static func developerIds(fromList json: [String: Any]?) -> [String] {
        let data = json?["data"] as? [String: Any]
        guard let list = data?["list"] as? [Any] else { return [] }
        var seen = Set<String>()
        var ids: [String] = []
        for case let item as [String: Any] in list {
            let id = normalizeDeveloperId(item["developer_id"])
                ?? normalizeDeveloperId(item["developerId"])
                ?? normalizeDeveloperId(item["id"])
            if let id = id, !seen.contains(id) {
                seen.insert(id)
                ids.append(id)
            }
        }
        return ids
    }

    /// 工作室字段优先级与桌面版 normalizeStudio 一致。
    static func studio(from item: [String: Any]) -> StudioRecord? {
        let id = normalizeDeveloperId(item["developer_id"])
            ?? normalizeDeveloperId(item["developerId"])
            ?? normalizeDeveloperId(item["id"])
            ?? nonEmpty(safeString(item["developer_id"]))
            ?? nonEmpty(safeString(item["id"]))
        guard let studioID = id else { return nil }
        var name = safeString(item["name"])
        if name.isEmpty { name = safeString(item["nickname"]) }
        if name.isEmpty { name = "开发者 " + String(studioID.suffix(4)) }
        let logo = normalizeURL(firstNonBlank(item, [
            "logo", "developer_logo", "developerLogo", "avatar", "icon", "avatar_url", "logo_url",
        ]))
        return StudioRecord(id: studioID, name: name, logo: logo)
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    /// 汇总 /me 与 /list 的结果：昵称、头像、工作室列表。
    static func probe(me: APIResponse?, list: APIResponse?) -> ProbedIdentity {
        var nickname = ""
        var avatar = ""
        if isSuccess(me), let data = me?.json?["data"] as? [String: Any] {
            let user = data["user"] as? [String: Any]
            let profile = data["profile"] as? [String: Any]
            nickname = firstNonBlank(data, ["nickname", "name", "username"])
            if nickname.isEmpty { nickname = firstNonBlank(user, ["nickname", "name", "username"]) }
            if nickname.isEmpty { nickname = firstNonBlank(profile, ["nickname", "name", "username"]) }
            avatar = normalizeURL(firstNonBlank(data, [
                "avatar", "avatar_url", "avatarUrl", "photo", "icon", "headimg", "head_img",
            ]))
            if avatar.isEmpty {
                avatar = normalizeURL(firstNonBlank(user, ["avatar", "avatar_url", "avatarUrl", "photo", "icon"]))
            }
            if avatar.isEmpty {
                avatar = normalizeURL(firstNonBlank(profile, ["avatar", "avatar_url", "avatarUrl", "photo", "icon"]))
            }
        }

        var studios: [StudioRecord]? = nil
        if isSuccess(list), let json = list?.json {
            let data = json["data"] as? [String: Any]
            if let items = data?["list"] as? [Any] {
                studios = items.compactMap { item -> StudioRecord? in
                    guard let dict = item as? [String: Any] else { return nil }
                    return studio(from: dict)
                }
            }
        }
        return ProbedIdentity(
            meDeveloperId: developerId(fromMe: me?.json),
            nickname: nickname,
            avatar: avatar,
            studios: studios
        )
    }

    /// 会话分类（对齐 account-state.js 的 classifySessionIdentity）
    static func classify(me: APIResponse?, list: APIResponse?, configuredDeveloperId: String?) -> SessionClassification {
        guard let me = me else {
            return SessionClassification(status: .unauthenticated, developerId: nil, error: nil)
        }
        if me.status == 401 || me.status == 403 {
            return SessionClassification(status: .unauthenticated, developerId: nil, error: nil)
        }
        if me.status == 0 || me.error != nil {
            return SessionClassification(status: .error, developerId: nil, error: me.error ?? "network_error")
        }
        if let id = developerId(fromMe: me.json) {
            return SessionClassification(status: .ready, developerId: id, error: nil)
        }
        guard let list = list, list.status != 0, list.error == nil else {
            return SessionClassification(status: .error, developerId: nil, error: list?.error ?? "identity_unavailable")
        }
        guard (200..<300).contains(list.status) else {
            return SessionClassification(status: .error, developerId: nil, error: "HTTP \(list.status)")
        }
        let ids = developerIds(fromList: list.json)
        if ids.isEmpty {
            return SessionClassification(status: .noDeveloper, developerId: nil, error: nil)
        }
        if let configured = normalizeDeveloperId(configuredDeveloperId), ids.contains(configured) {
            return SessionClassification(status: .ready, developerId: configured, error: nil)
        }
        return SessionClassification(status: .ready, developerId: ids[0], error: nil)
    }

    /// 从页面地址里识别开发者 ID（登录窗口里进入开发者控制台时使用）
    static func developerId(fromURL urlString: String) -> String? {
        let patterns = [
            #"/(?:v3|developer|developer-center)/(\d+)(?:/|$)"#,
            #"[?&](?:developer_id|developerId|developerID)=(\d+)"#,
        ]
        let range = NSRange(urlString.startIndex..., in: urlString)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: urlString, range: range),
                  match.numberOfRanges > 1,
                  let group = Range(match.range(at: 1), in: urlString) else { continue }
            return String(urlString[group])
        }
        return nil
    }

    /// 原生 fetch 只允许访问 TapTap 域名，避免页面把桥当成任意代理使用。
    static func isAllowedAPIURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "taptap.cn" || host.hasSuffix(".taptap.cn") || host == "taptap.com" || host.hasSuffix(".taptap.com")
    }

    // MARK: - 更新检查

    /// 数字版本号比较：1.0.10 > 1.0.9
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 只读取 ios_version 字段，避免把 Android 的 version_code 误判为 iOS 更新。
    static func updateInfo(from json: [String: Any], localVersion: String) -> UpdateInfo? {
        let version = safeString(json["ios_version"])
        guard !version.isEmpty, isVersion(version, newerThan: localVersion) else { return nil }
        let url = normalizeURL(firstNonBlank(json, ["ios_url", "app_store_url", "testflight_url", "download_page"]))
        var notes = safeString(json["update_notes"])
        if notes.isEmpty { notes = safeString(json["notes"]) }
        let forceValue = json["force_update"]
        let force = (forceValue as? Bool) == true || ((forceValue as? NSNumber)?.intValue == 1)
        return UpdateInfo(version: version, url: url, notes: notes, force: force)
    }
}
