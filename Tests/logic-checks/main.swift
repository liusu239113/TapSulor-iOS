// 纯逻辑检查：与 TapSulor/Sources/Core 一起编译，在 macOS 命令行直接运行。
// 运行方式：bash Tests/run-logic-checks.sh
import Foundation

var passes = 0
var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL: \(label)")
    }
}

// MARK: 1. 开发者 ID 规范化
check(TapTapLogic.normalizeDeveloperId("381509") == "381509", "字符串 ID")
check(TapTapLogic.normalizeDeveloperId("381509.0") == "381509", "形如 381509.0 的 ID")
check(TapTapLogic.normalizeDeveloperId(" 12 ") == "12", "去掉首尾空白")
check(TapTapLogic.normalizeDeveloperId("abc") == nil, "非数字被拒绝")
check(TapTapLogic.normalizeDeveloperId(NSNumber(value: 381509)) == "381509", "数字类型的 ID")
check(TapTapLogic.normalizeDeveloperId(NSNumber(value: 1.5)) == nil, "小数被拒绝")
check(TapTapLogic.normalizeDeveloperId(nil) == nil, "nil 被拒绝")

// MARK: 2. /me 与 /list 解析
let meA: [String: Any] = ["data": ["developer_id": NSNumber(value: 381509), "nickname": "小明"]]
let meB: [String: Any] = ["data": ["developerId": "777"]]
let meC: [String: Any] = ["data": ["developer": ["id": "888"]]]
let meD: [String: Any] = ["data": ["user": ["nickname": "x"]]]
check(TapTapLogic.developerId(fromMe: meA) == "381509", "me 中的 developer_id（数字）")
check(TapTapLogic.developerId(fromMe: meB) == "777", "me 中的 developerId")
check(TapTapLogic.developerId(fromMe: meC) == "888", "me 中的 developer.id")
check(TapTapLogic.developerId(fromMe: meD) == nil, "me 中没有 ID")

let listJSON: [String: Any] = ["data": ["list": [
    ["developer_id": "1"],
    ["developerId": "2"],
    ["id": "2"],
    ["id": "abc"],
    ["name": "没有 ID"],
    ["id": NSNumber(value: 3)],
]]]
check(TapTapLogic.developerIds(fromList: listJSON) == ["1", "2", "3"], "列表 ID 去重并跳过无效项")

let probe = TapTapLogic.probe(
    me: APIResponse(status: 200, json: ["data": ["developer_id": NSNumber(value: 1), "nickname": "n", "avatar": "//cdn/x.png"]], error: nil),
    list: APIResponse(status: 200, json: ["data": ["list": [["developer_id": "1", "name": "A", "logo": "https://l"]]]], error: nil)
)
check(probe.meDeveloperId == "1", "probe: 开发者 ID")
check(probe.nickname == "n", "probe: 昵称")
check(probe.avatar == "https://cdn/x.png", "probe: 协议相对头像补全为 https")
check(probe.studios?.first?.logo == "https://l", "probe: 工作室头像")

// MARK: 3. 会话分类
func ok(_ json: [String: Any]) -> APIResponse {
    APIResponse(status: 200, json: json, error: nil)
}
check(TapTapLogic.classify(me: APIResponse(status: 401, json: nil, error: nil), list: nil, configuredDeveloperId: nil).status == .unauthenticated, "401 -> 未登录")
check(TapTapLogic.classify(me: .failure("offline"), list: nil, configuredDeveloperId: nil).status == .error, "网络错误 -> error")
check(TapTapLogic.classify(me: ok(meA), list: nil, configuredDeveloperId: nil)
        == SessionClassification(status: .ready, developerId: "381509", error: nil), "me 有 ID -> ready")
check(TapTapLogic.classify(me: ok(["data": [:]]), list: ok(["data": ["list": []]]), configuredDeveloperId: nil).status == .noDeveloper, "没有任何开发者 -> no-developer")
check(TapTapLogic.classify(me: ok(["data": [:]]), list: ok(listJSON), configuredDeveloperId: "2").developerId == "2", "配置的 ID 优先")
check(TapTapLogic.classify(me: ok(["data": [:]]), list: ok(listJSON), configuredDeveloperId: "999").developerId == "1", "配置的 ID 不在列表时取第一个")
check(TapTapLogic.classify(me: ok(["data": [:]]), list: APIResponse(status: 500, json: nil, error: nil), configuredDeveloperId: nil).status == .error, "列表 HTTP 500 -> error")
check(TapTapLogic.classify(me: ok(["data": [:]]), list: .failure("timeout"), configuredDeveloperId: nil).status == .error, "列表网络错误 -> error")

// MARK: 4. 从页面地址识别开发者 ID
check(TapTapLogic.developerId(fromURL: "https://developer.taptap.cn/v3/381509/app") == "381509", "地址路径中的 ID")
check(TapTapLogic.developerId(fromURL: "https://developer.taptap.cn/app/list?developer_id=12345&x=1") == "12345", "地址参数中的 ID")
check(TapTapLogic.developerId(fromURL: "https://developer.taptap.cn/") == nil, "地址中没有 ID")

// MARK: 5. 原生 fetch 的域名白名单
check(TapTapLogic.isAllowedAPIURL(URL(string: "https://developer.taptap.cn/api/x")!), "允许 TapTap https 域名")
check(!TapTapLogic.isAllowedAPIURL(URL(string: "http://developer.taptap.cn/api/x")!), "拒绝 http")
check(!TapTapLogic.isAllowedAPIURL(URL(string: "https://evil.example.com/")!), "拒绝其它域名")
check(!TapTapLogic.isAllowedAPIURL(URL(string: "https://taptap.cn.example.com/")!), "拒绝仿冒域名")

// MARK: 6. 版本比较与更新信息
check(TapTapLogic.isVersion("1.0.10", newerThan: "1.0.9"), "数字比较 1.0.10 > 1.0.9")
check(!TapTapLogic.isVersion("1.0.5", newerThan: "1.0.5"), "相同版本不算更新")
check(TapTapLogic.updateInfo(from: ["ios_version": "1.0.6", "ios_url": "https://x.example/app"], localVersion: "1.0.5")?.version == "1.0.6", "发现 iOS 新版本")
check(TapTapLogic.updateInfo(from: ["version_code": 9, "latest_version": "9.9"], localVersion: "1.0.5") == nil, "只看 ios_version，忽略 Android 字段")

// MARK: 7. Cookie 请求头
let now = Date()
let cookies = [
    CookieRecord(name: "sessionid", value: "abc", domain: ".taptap.cn", path: "/", isSecure: true, expiresDate: nil),
    CookieRecord(name: "old", value: "1", domain: "developer.taptap.cn", path: "/", isSecure: false, expiresDate: now.addingTimeInterval(-10)),
    CookieRecord(name: "other", value: "2", domain: ".example.com", path: "/", isSecure: false, expiresDate: nil),
    CookieRecord(name: "api", value: "3", domain: "developer.taptap.cn", path: "/api", isSecure: false, expiresDate: nil),
]
check(CookieHeader.header(for: URL(string: "https://developer.taptap.cn/api/user/v1/me")!, cookies: cookies, now: now) == "sessionid=abc; api=3", "按域名、路径、过期时间筛选")
check(CookieHeader.header(for: URL(string: "http://developer.taptap.cn/api/x")!, cookies: cookies, now: now) == "api=3", "Secure Cookie 不随 http 发送")
check(CookieHeader.header(for: URL(string: "https://developer.taptap.cn/")!, cookies: cookies, now: now) == "sessionid=abc", "路径限制生效")
check(CookieHeader.hasSessionCookie(cookies), "识别登录态 Cookie")
check(!CookieHeader.hasSessionCookie([CookieRecord(name: "lang", value: "zh", domain: ".taptap.cn", path: "/", isSecure: false, expiresDate: nil)]), "普通 Cookie 不算登录态")

// MARK: 8. 账号仓库规则
let store = AccountStore(fileURL: nil)
let profileA = IdentityProfile(
    nickname: "甲",
    avatar: "https://img/a.png",
    developerName: "甲工作室",
    developerAvatar: "",
    studios: [
        StudioRecord(id: "381509", name: "甲工作室", logo: "https://img/s1.png"),
        StudioRecord(id: "555", name: "乙工作室", logo: ""),
    ]
)
let outcomeA = store.applyLogin(developerId: "381509", profile: profileA, loginStoreId: "store-1", mode: .login)
check(outcomeA.isNew && outcomeA.keptLoginStore && outcomeA.staleStoreId == nil, "首次登录新建账号")
check(store.current?.developerId == "381509", "首次登录设为当前账号")
check(store.activeDeveloperId == "381509", "默认生效的开发者 ID 为账号的 developerId")

let outcomeA2 = store.applyLogin(developerId: "381509", profile: IdentityProfile(), loginStoreId: "store-2", mode: .login)
check(!outcomeA2.isNew && outcomeA2.staleStoreId == "store-1" && store.accounts.count == 1, "重新登录替换存储，并返回旧存储")
check(store.current?.storeId == "store-2", "重新登录后账号使用新存储")

check(store.setActiveStudio(developerId: "555"), "切换工作室")
check(store.activeDeveloperId == "555", "记录选中的工作室")
check(store.current?.developerName == "乙工作室", "显示名称跟随选中的工作室")
check(store.current?.studios.count == 2, "重新登录时保留工作室列表")

let outcomeB = store.applyLogin(developerId: "999", profile: IdentityProfile(nickname: "丙"), loginStoreId: "store-3", mode: .add)
check(outcomeB.isNew && !outcomeB.switched && outcomeB.keptLoginStore, "add 模式新建账号但不切换")
check(store.current?.developerId == "381509", "add 之后当前账号不变")
check(store.accounts.count == 2, "共两个账号")

let outcomeC = store.applyLogin(developerId: "999", profile: IdentityProfile(), loginStoreId: "store-4", mode: .add)
check(!outcomeC.isNew && !outcomeC.keptLoginStore && outcomeC.staleStoreId == nil, "add 对已有账号不替换存储")
check(store.account(id: outcomeB.account.id)?.storeId == "store-3", "已有账号仍使用原存储")

let currentID = store.current!.id
let removed = store.remove(id: currentID)
check(removed?.currentChanged == true && store.current != nil, "删除当前账号后切换到剩余账号")
check(store.remove(id: "missing") == nil, "删除不存在的账号返回 nil")

let fresh = AccountStore(fileURL: nil)
let adopted = fresh.applySession(developerId: "42", profile: IdentityProfile(nickname: "默认会话"))
check(adopted?.storeId == nil && fresh.current?.developerId == "42", "没有账号时收养默认存储中的会话")

// MARK: 9. accounts.json 往返
let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("tapsulor-check-\(UUID().uuidString)")
let tmpFile = tmpDir.appendingPathComponent("accounts.json")
let persisted = AccountStore(fileURL: tmpFile)
_ = persisted.applyLogin(developerId: "7", profile: IdentityProfile(nickname: "持久化"), loginStoreId: "s-7", mode: .login)
let reloaded = AccountStore(fileURL: tmpFile)
check(reloaded.accounts.count == 1 && reloaded.current?.storeId == "s-7" && reloaded.current?.nickname == "持久化", "accounts.json 读写往返一致")
try? FileManager.default.removeItem(at: tmpDir)

print("通过 \(passes) 项，失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
