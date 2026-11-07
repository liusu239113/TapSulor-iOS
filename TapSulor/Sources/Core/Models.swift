import Foundation

// 数据模型。与 WebKit / UIKit 无关，便于在 macOS 上做逻辑检查（见 Tests/run-logic-checks.sh）。

/// 工作室（开发者主体）。字段与桌面版 normalizeStudio 的输出一致：{ id, name, logo }。
struct StudioRecord: Codable, Equatable {
    var id: String
    var name: String
    var logo: String
}

/// 本地保存的 TapTap 开发者账号（accounts.json 中的一项）。
struct AccountRecord: Codable, Equatable {
    var id: String
    var name: String
    var developerId: String
    var developerName: String
    var developerAvatar: String
    var nickname: String
    var avatar: String
    /// WKWebsiteDataStore 的标识（UUID 字符串）。nil 表示系统默认存储。
    var storeId: String?
    var studios: [StudioRecord]
    /// 切换工作室后选中的开发者 ID；nil 时使用 developerId。
    var activeDeveloperId: String?
}

/// accounts.json 的根结构：{ current, accounts }，与桌面版保持一致。
struct AccountsFile: Codable, Equatable {
    var current: String?
    var accounts: [AccountRecord]
}

/// 登录窗口的模式。页面传来的 mode 可能是 null / "login" / "developer" / "add"。
enum LoginMode: String {
    case login
    case developer
    case add

    init(bridgeValue: Any?) {
        let raw = (bridgeValue as? String)?.lowercased() ?? "login"
        self = LoginMode(rawValue: raw) ?? .login
    }
}

/// 从 TapTap 接口解析出的身份资料。studios 为 nil 表示没有拿到工作室列表，保留原有数据。
struct IdentityProfile: Equatable {
    var nickname: String = ""
    var avatar: String = ""
    var developerName: String = ""
    var developerAvatar: String = ""
    var studios: [StudioRecord]? = nil
}

/// 一次网络请求的结果。status == 0 表示网络层失败，error 有值。
struct APIResponse {
    var status: Int
    var json: [String: Any]?
    var error: String?
    /// 原始响应文本（原生 fetch 接口需要原样返回给页面）
    var body: String? = nil

    static func failure(_ message: String) -> APIResponse {
        APIResponse(status: 0, json: nil, error: message)
    }
}

/// 会话状态，对应页面 checkLogin() 返回的 status。
enum SessionStatus: String {
    case ready
    case unauthenticated
    case noDeveloper = "no-developer"
    case error
}

struct SessionClassification: Equatable {
    var status: SessionStatus
    var developerId: String?
    var error: String?
}

/// 发现的新版本信息（来自更新服务器的 version.json）。
struct UpdateInfo: Equatable {
    var version: String
    var url: String
    var notes: String
    var force: Bool
}
