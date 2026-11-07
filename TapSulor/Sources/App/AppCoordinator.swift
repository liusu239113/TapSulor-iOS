import Foundation
import UIKit
import WebKit

/// 一次登录流程的状态
@MainActor
final class LoginSession {
    let mode: LoginMode
    /// 登录使用的新数据存储（每次登录都是全新的存储，避免串号）
    let storeId: String
    weak var sheet: WebSheetViewController?
    var resolved = false
    var nativeAttempts = 0
    var pendingTasks: [Task<Void, Never>] = []

    init(mode: LoginMode, storeId: String) {
        self.mode = mode
        self.storeId = storeId
    }

    func cancelPending() {
        pendingTasks.forEach { $0.cancel() }
        pendingTasks.removeAll()
    }
}

/// 应用调度中心：账号仓库、原生网络、WKWebView 数据存储、登录流程与原生桥消息。
@MainActor
final class AppCoordinator {
    static let appVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.5"

    let accountStore: AccountStore
    private let api = TapTapAPI()
    private weak var mainViewController: MainViewController?
    private var loginSession: LoginSession?
    private var tickTimer: Timer?
    private var hasActivatedOnce = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("TapSulor", isDirectory: true)
        accountStore = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
    }

    var webRootURL: URL {
        Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true)
    }

    var indexURL: URL {
        webRootURL.appendingPathComponent("index.html")
    }

    func attach(_ controller: MainViewController) {
        mainViewController = controller
    }

    /// 启动后 3 秒静默检查更新（对齐安卓版 UpdateChecker 的冷启动行为）
    func start() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self.runUpdateCheck(silent: true)
        }
    }

    // MARK: - 生命周期

    func appDidBecomeActive() {
        if hasActivatedOnce {
            fireEvent("__onAppResume")
        }
        hasActivatedOnce = true
        tickTimer?.invalidate()
        // 对齐桌面版与安卓版的 5 分钟后台轮询（仅在前台运行时生效）
        tickTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fireEvent("__onAppBackgroundTick")
            }
        }
    }

    func appWillResignActive() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - WebKit 配置与存储

    /// 账号对应的数据存储；没有账号或 storeId 为空时使用系统默认存储
    func dataStore(for storeId: String?) -> WKWebsiteDataStore {
        guard let storeId = storeId, let uuid = UUID(uuidString: storeId) else {
            return WKWebsiteDataStore.default()
        }
        return WKWebsiteDataStore(forIdentifier: uuid)
    }

    /// 延迟删除数据存储，等待正在使用它的 WKWebView 释放
    private func scheduleStoreDeletion(_ storeId: String?) {
        guard let storeId = storeId, let uuid = UUID(uuidString: storeId) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            WKWebsiteDataStore.remove(forIdentifier: uuid) { error in
                if let error = error {
                    NSLog("[store] 删除数据存储失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 读取某个存储里的全部 Cookie（转换为与 WebKit 无关的记录）
    private func cookies(for storeId: String?) async -> [CookieRecord] {
        let store = dataStore(for: storeId)
        return await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                let records = cookies.map { cookie in
                    CookieRecord(name: cookie.name, value: cookie.value, domain: cookie.domain,
                                 path: cookie.path, isSecure: cookie.isSecure, expiresDate: cookie.expiresDate)
                }
                continuation.resume(returning: records)
            }
        }
    }

    func makeMainConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore(for: accountStore.current?.storeId)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let controller = WKUserContentController()
        // 先注入初始状态，再注入原生桥（android-bridge.js 由页面自己加载，会包装这里的 AndroidBridge）
        controller.addUserScript(WKUserScript(source: initialStateScript(),
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let shim = try? String(contentsOf: webRootURL.appendingPathComponent("ios-bridge.js"), encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: shim,
                                                  injectionTime: .atDocumentStart, forMainFrameOnly: true))
        } else {
            NSLog("[bridge] 找不到 Web/ios-bridge.js，页面将无法使用原生功能")
        }
        controller.add(WebBridge(coordinator: self), name: WebBridge.handlerName)
        configuration.userContentController = controller
        return configuration
    }

    // MARK: - 状态

    func stateObject() -> [String: Any] {
        [
            "current": (accountStore.current?.id).jsonValue,
            "accounts": JSONSupport.object(from: accountStore.accounts),
            "studios": JSONSupport.object(from: accountStore.current?.studios ?? []),
            "activeDeveloperId": accountStore.activeDeveloperId.jsonValue,
            "appVersion": AppCoordinator.appVersion,
        ]
    }

    private func initialStateScript() -> String {
        "window.__nativeState = " + JSONSupport.string(from: stateObject()) + ";"
    }

    private func pushState() {
        mainViewController?.pushNativeState(JSONSupport.string(from: stateObject()))
    }

    private func fireEvent(_ name: String, payload: String? = nil) {
        guard let web = mainViewController?.webView else { return }
        if let payload = payload {
            web.callPage("if (typeof window.\(name) === 'function') { window.\(name)(JSON.parse(payload)); }",
                         arguments: ["payload": payload])
        } else {
            web.callPage("if (typeof window.\(name) === 'function') { window.\(name)(); }")
        }
    }

    private func fireAccountUpdated(isNew: Bool, alreadyCurrent: Bool, switched: Bool, developerId: String?) {
        let payload: [String: Any] = [
            "isNew": isNew,
            "alreadyCurrent": alreadyCurrent,
            "switched": switched,
            "developerId": developerId.jsonValue,
        ]
        fireEvent("__onAccountUpdated", payload: JSONSupport.string(from: payload))
    }

    /// 当前账号或其存储变化：重建页面，页面会在新存储上重新初始化
    private func rebuildMain() {
        mainViewController?.rebuildWebView()
    }

    // MARK: - 原生桥消息（页面 -> 原生）

    func handleBridge(op: String, body: [String: Any], webView: WKWebView?) {
        #if DEBUG
        NSLog("[debug] bridge op=\(op)")
        #endif
        let reply = webView ?? mainViewController?.webView
        switch op {
        case "fetch", "replayApi":
            guard let seq = body["seq"], let urlText = body["url"] as? String else { return }
            let function = op == "fetch"
                ? "window.__pendingFetchResolve(seq, payload);"
                : "window.__pendingReplayResolve(seq, payload);"
            Task { @MainActor in
                let result = await self.proxyGET(urlText)
                reply?.callPage(function, arguments: ["seq": seq, "payload": JSONSupport.string(from: result)])
            }

        case "replayKeyApis":
            let result: [String: Any] = ["count": 0, "saved": false]
            reply?.callPage("window.__pendingReplayKeyResolve(payload);",
                            arguments: ["payload": JSONSupport.string(from: result)])

        case "checkLogin":
            Task { @MainActor in
                let result = await self.checkLogin()
                reply?.callPage("window.__pendingLoginResolve(payload);",
                                arguments: ["payload": JSONSupport.string(from: result)])
            }

        case "openLogin":
            presentLogin(mode: LoginMode(bridgeValue: body["mode"]))

        case "switchStudio":
            if let developerId = body["developerId"] as? String, accountStore.setActiveStudio(developerId: developerId) {
                rebuildMain()
            }

        case "switchAccount":
            switchAccount(id: body["id"] as? String ?? "")

        case "addAccount":
            let name = body["name"] as? String ?? ""
            let developerId = body["developerId"] as? String ?? ""
            let wasSignedOut = accountStore.current == nil
            if accountStore.addAccount(name: name, developerId: developerId, storeId: UUID().uuidString) != nil {
                if wasSignedOut { rebuildMain() } else { pushState() }
            }

        case "removeAccount":
            guard let id = body["id"] as? String, let result = accountStore.remove(id: id) else { return }
            if result.currentChanged {
                rebuildMain()
            } else {
                pushState()
            }
            scheduleStoreDeletion(result.removed.storeId)

        case "openGameBackend":
            openBackend(title: body["name"] as? String ?? "")

        case "checkUpdate":
            Task { @MainActor in
                await self.runUpdateCheck(silent: false)
            }

        case "syncPreferences":
            let mode = body["mode"] as? String ?? "light"
            UserDefaults.standard.set(mode, forKey: "taptap_theme_mode")
            mainViewController?.applyTheme(dark: mode == "dark")

        default:
            NSLog("[bridge] 未知操作：\(op)")
        }
    }

    // MARK: - 账号操作

    private func switchAccount(id: String) {
        guard let target = accountStore.account(id: id) else {
            fireAccountUpdated(isNew: false, alreadyCurrent: false, switched: false, developerId: nil)
            return
        }
        if accountStore.current?.id == id {
            fireAccountUpdated(isNew: false, alreadyCurrent: true, switched: false, developerId: target.developerId)
            return
        }
        _ = accountStore.setCurrent(id: id)
        rebuildMain()
    }

    // MARK: - 原生网络（页面 -> 原生 -> TapTap）

    /// 代理 GET 请求，结果格式与桌面版 bridge:fetch 相同：{ ok, status, body, error }
    private func proxyGET(_ urlText: String) async -> [String: Any] {
        guard let url = URL(string: urlText), TapTapLogic.isAllowedAPIURL(url) else {
            return ["ok": false, "status": 0, "body": NSNull(), "error": "不允许访问该地址"]
        }
        let cookies = await cookies(for: accountStore.current?.storeId)
        let response = await api.get(url, cookies: cookies)
        if let error = response.error {
            return ["ok": false, "status": 0, "body": NSNull(), "error": error]
        }
        return [
            "ok": (200..<300).contains(response.status),
            "status": response.status,
            "body": response.body.jsonValue,
            "error": NSNull(),
        ]
    }

    /// 检查登录态（对齐 account-state.js 的分类，并同步账号资料）
    private func checkLogin() async -> [String: Any] {
        let account = accountStore.current
        let cookies = await cookies(for: account?.storeId)
        if account == nil && !CookieHeader.hasSessionCookie(cookies) {
            return sessionPayload(status: .unauthenticated)
        }

        let identity = await api.fetchIdentity(cookies: cookies)
        let classification = TapTapLogic.classify(
            me: identity.me,
            list: identity.list,
            configuredDeveloperId: account.map { $0.activeDeveloperId ?? $0.developerId })
        guard classification.status == .ready, let developerId = classification.developerId else {
            return sessionPayload(status: classification.status, error: classification.error)
        }

        let probe = TapTapLogic.probe(me: identity.me, list: identity.list)
        let profile = profileFrom(probe)
        let previousCurrentId = accountStore.current?.id
        guard let record = accountStore.applySession(developerId: developerId, profile: profile) else {
            return sessionPayload(status: .unauthenticated)
        }
        if record.id != previousCurrentId {
            // 会话属于另一个账号的存储：切换页面到那个存储
            rebuildMain()
        } else {
            pushState()
        }

        let effectiveId = record.activeDeveloperId ?? record.developerId
        let picked = record.studios.first { $0.id == effectiveId }
        let profilePayload: [String: Any] = [
            "nickname": probe.nickname,
            "avatar": probe.avatar,
            "developerName": picked?.name ?? (record.developerName.isEmpty ? probe.nickname : record.developerName),
            "developerAvatar": picked?.logo ?? record.developerAvatar,
        ]
        return [
            "status": SessionStatus.ready.rawValue,
            "developerId": effectiveId,
            "error": NSNull(),
            "profile": profilePayload,
            "studios": JSONSupport.object(from: record.studios),
        ]
    }

    private func sessionPayload(status: SessionStatus, error: String? = nil) -> [String: Any] {
        [
            "status": status.rawValue,
            "developerId": NSNull(),
            "error": error.jsonValue,
            "profile": NSNull(),
            "studios": [[String: Any]](),
        ]
    }

    private func profileFrom(_ probe: TapTapLogic.ProbedIdentity) -> IdentityProfile {
        IdentityProfile(nickname: probe.nickname, avatar: probe.avatar, studios: probe.studios)
    }

    // MARK: - 登录流程（对齐桌面版 openLogin）

    private func presentLogin(mode: LoginMode) {
        #if DEBUG
        NSLog("[debug] presentLogin mode=\(mode)")
        #endif
        guard loginSession == nil, let presenter = AlertPresenter.topViewController() else { return }

        // 每次登录都使用全新的数据存储
        let storeId = UUID().uuidString
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore(for: storeId)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let session = LoginSession(mode: mode, storeId: storeId)
        loginSession = session

        let sheet = WebSheetViewController(
            title: "TapTap 开发者登录",
            url: URL(string: TapTapLogic.origin + "/")!,
            configuration: configuration)
        sheet.onPageChanged = { [weak self, weak session] url in
            guard let self = self, let session = session else { return }
            self.handleLoginPage(url: url, session: session)
        }
        sheet.onClosed = { [weak self, weak session] in
            guard let self = self, let session = session else { return }
            self.handleLoginCancelled(session)
        }
        session.sheet = sheet

        let navigation = UINavigationController(rootViewController: sheet)
        navigation.modalPresentationStyle = .pageSheet
        presenter.present(navigation, animated: true)
    }

    private func handleLoginPage(url: URL, session: LoginSession) {
        #if DEBUG
        NSLog("[debug] login page url=\(url.absoluteString)")
        #endif
        guard !session.resolved else { return }
        // 进入开发者控制台的地址里直接带有开发者 ID
        if let developerId = TapTapLogic.developerId(fromURL: url.absoluteString) {
            Task { @MainActor in
                await self.finishLogin(session: session, developerId: developerId)
            }
            return
        }
        // 否则延迟检查：先用页面自己的会话（0.9 秒），再用原生请求（1.4 秒起，每 1.8 秒重试，最多 12 次）
        session.cancelPending()
        session.pendingTasks.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            await self.pageCheck(session: session)
        })
        session.pendingTasks.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await self.nativeCheck(session: session)
        })
    }

    private func pageCheck(session: LoginSession) async {
        guard !session.resolved, !Task.isCancelled, let sheet = session.sheet else { return }
        guard let developerId = await sheet.webView.evaluatePage(PageScripts.developerIdFromSession) as? String else {
            return
        }
        await finishLogin(session: session, developerId: developerId)
    }

    private func nativeCheck(session: LoginSession) async {
        guard !session.resolved, !Task.isCancelled, session.nativeAttempts < 12 else { return }
        session.nativeAttempts += 1
        let cookies = await cookies(for: session.storeId)
        let identity = await api.fetchIdentity(cookies: cookies)
        let classification = TapTapLogic.classify(me: identity.me, list: identity.list, configuredDeveloperId: nil)
        if classification.status == .ready, let developerId = classification.developerId, !session.resolved {
            let probe = TapTapLogic.probe(me: identity.me, list: identity.list)
            completeLogin(session: session, developerId: developerId, profile: profileFrom(probe))
            return
        }
        session.pendingTasks.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await self.nativeCheck(session: session)
        })
    }

    private func finishLogin(session: LoginSession, developerId: String) async {
        guard !session.resolved else { return }
        let cookies = await cookies(for: session.storeId)
        let identity = await api.fetchIdentity(cookies: cookies)
        completeLogin(session: session, developerId: developerId,
                      profile: profileFrom(TapTapLogic.probe(me: identity.me, list: identity.list)))
    }

    private func completeLogin(session: LoginSession, developerId: String, profile: IdentityProfile) {
        #if DEBUG
        NSLog("[debug] login complete developerId=\(developerId)")
        #endif
        guard !session.resolved else { return }
        session.resolved = true
        session.cancelPending()
        let outcome = accountStore.applyLogin(
            developerId: developerId, profile: profile, loginStoreId: session.storeId, mode: session.mode)

        if let navigation = session.sheet?.navigationController {
            navigation.dismiss(animated: true) { [weak self] in
                self?.finishLoginSheet(session: session, outcome: outcome)
            }
        } else {
            finishLoginSheet(session: session, outcome: outcome)
        }
    }

    private func finishLoginSheet(session: LoginSession, outcome: AccountStore.LoginOutcome) {
        if loginSession === session {
            loginSession = nil
        }
        if !outcome.keptLoginStore {
            scheduleStoreDeletion(session.storeId)
        }
        if session.mode == .add {
            // 添加账号：当前账号不变，页面保持原样，只通知结果
            pushState()
            fireEvent("__onLoginSuccess")
            fireAccountUpdated(isNew: outcome.isNew, alreadyCurrent: false,
                               switched: outcome.switched, developerId: outcome.account.developerId)
            fireEvent("__onLoginCheck")
        } else {
            // 登录或切换到该账号：替换旧存储并重建页面
            if let stale = outcome.staleStoreId {
                scheduleStoreDeletion(stale)
            }
            rebuildMain()
        }
    }

    private func handleLoginCancelled(_ session: LoginSession) {
        #if DEBUG
        NSLog("[debug] login cancelled (resolved=\(session.resolved))")
        #endif
        guard !session.resolved, loginSession === session else { return }
        session.resolved = true
        session.cancelPending()
        loginSession = nil
        scheduleStoreDeletion(session.storeId)
        fireEvent("__onLoginCheck")
    }

    // MARK: - 游戏后台（对齐安卓版 BackendWebViewActivity，地址为 maker.taptap.cn）

    private func openBackend(title: String) {
        guard let presenter = AlertPresenter.topViewController() else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore(for: accountStore.current?.storeId)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let sheet = WebSheetViewController(
            title: title.isEmpty ? "游戏后台" : title,
            url: URL(string: "https://maker.taptap.cn/")!,
            configuration: configuration)
        presenter.present(UINavigationController(rootViewController: sheet), animated: true)
    }

    // MARK: - 更新检查

    private func runUpdateCheck(silent: Bool) async {
        let outcome = await UpdateChecker.check()
        switch outcome {
        case .failed:
            if !silent {
                AlertPresenter.show(title: "检查更新失败", message: "无法连接到更新服务器，请稍后再试。")
            }
        case .upToDate:
            if !silent {
                AlertPresenter.show(title: "已是最新版本", message: "当前版本 \(AppCoordinator.appVersion) 已是最新。")
            }
        case .available(let info):
            if silent && info.url.isEmpty { return }
            var message = "当前版本 \(AppCoordinator.appVersion)\n最新版本 \(info.version)"
            if !info.notes.isEmpty {
                message += "\n\n更新内容：\n\(info.notes)"
            }
            guard let link = URL(string: info.url), !info.url.isEmpty else {
                AlertPresenter.show(title: "发现新版本", message: message + "\n\n（暂未提供 iOS 下载链接）")
                return
            }
            AlertPresenter.show(
                title: info.force ? "发现重要更新" : "发现新版本",
                message: message,
                confirm: "立即更新",
                cancel: info.force ? nil : "稍后",
                onConfirm: { UIApplication.shared.open(link, options: [:], completionHandler: nil) })
        }
    }
}
