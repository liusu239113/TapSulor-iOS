import Foundation

/// 与 WebKit 解耦的 Cookie 记录（由 WKHTTPCookieStore 的 HTTPCookie 转换而来）。
struct CookieRecord: Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var isSecure: Bool
    var expiresDate: Date?
}

enum CookieHeader {
    /// 按 RFC 6265 的常用规则（域名、路径、Secure、过期时间）生成 Cookie 请求头。
    static func header(for url: URL, cookies: [CookieRecord], now: Date = Date()) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let isHTTPS = url.scheme?.lowercased() == "https"
        let requestPath = url.path.isEmpty ? "/" : url.path
        var pairs: [String] = []
        for cookie in cookies {
            if let expires = cookie.expiresDate, expires <= now { continue }
            if cookie.isSecure && !isHTTPS { continue }
            var domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") { domain.removeFirst() }
            guard !domain.isEmpty, host == domain || host.hasSuffix("." + domain) else { continue }
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let prefix = cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/"
            guard requestPath == cookiePath || requestPath.hasPrefix(prefix) else { continue }
            pairs.append("\(cookie.name)=\(cookie.value)")
        }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }

    /// 与桌面版 checkLogin 的判断一致：存在已知的登录态 Cookie 即视为已登录。
    static func hasSessionCookie(_ cookies: [CookieRecord]) -> Bool {
        let knownNames: Set<String> = ["sessionid", "taptap_session", "sid", "taptap_access_token"]
        return cookies.contains { cookie in
            let known = knownNames.contains(cookie.name) || cookie.name.hasPrefix("tt_")
            return known && !cookie.value.isEmpty
        }
    }
}
