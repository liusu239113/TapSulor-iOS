import Foundation

/// 原生网络层。请求会带上账号存储里的 Cookie，请求头与桌面版 net.fetch 保持一致。
final class TapTapAPI {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        // Cookie 由我们自己从 WKHTTPCookieStore 读取并写入请求头，不让 URLSession 自行管理
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    static func url(_ path: String) -> URL {
        URL(string: TapTapLogic.origin + path)!
    }

    /// GET 请求（与桌面版 bridge:fetch 相同：只做 GET）
    func get(_ url: URL, cookies: [CookieRecord]) async -> APIResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(TapTapAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(TapTapLogic.origin + "/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let cookieHeader = CookieHeader.header(for: url, cookies: cookies) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return APIResponse(status: status, json: json, error: nil, body: String(decoding: data, as: UTF8.self))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// 同时请求 /me 与 /list（对齐桌面版 probeDeveloperId）。/me 返回 401/403 时不再请求 /list。
    func fetchIdentity(cookies: [CookieRecord]) async -> (me: APIResponse, list: APIResponse?) {
        let me = await get(TapTapAPI.url(TapTapLogic.mePath), cookies: cookies)
        if me.status == 401 || me.status == 403 {
            return (me, nil)
        }
        let list = await get(TapTapAPI.url(TapTapLogic.developerListPath), cookies: cookies)
        return (me, list)
    }
}
