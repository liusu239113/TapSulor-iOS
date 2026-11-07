import Foundation
import UIKit
import WebKit

/// 主界面：加载 Web 目录中的 index.html，与安卓版是同一套页面。
@MainActor
final class MainViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let coordinator: AppCoordinator
    private(set) var webView: WKWebView?
    private var isDarkTheme = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("MainViewController 不使用 storyboard")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 与页面保持一致的主题（页面自己的主题保存在 localStorage，这里用 syncPreferences 同步过的值）
        applyTheme(dark: UserDefaults.standard.string(forKey: "taptap_theme_mode") == "dark")
        rebuildWebView()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        isDarkTheme ? .lightContent : .darkContent
    }

    /// WKWebViewConfiguration 创建后不能更换数据存储，所以账号或存储变化时整体重建。
    /// 初始状态与原生桥脚本在创建时注入，因此重建后页面拿到的是最新状态。
    func rebuildWebView() {
        if let old = webView {
            old.stopLoading()
            old.removeFromSuperview()
            old.configuration.userContentController.removeScriptMessageHandler(forName: WebBridge.handlerName)
        }

        let newWebView = WKWebView(frame: .zero, configuration: coordinator.makeMainConfiguration())
        newWebView.translatesAutoresizingMaskIntoConstraints = false
        newWebView.navigationDelegate = self
        newWebView.uiDelegate = self
        newWebView.allowsBackForwardNavigationGestures = false
        newWebView.backgroundColor = view.backgroundColor
        newWebView.scrollView.backgroundColor = view.backgroundColor
        newWebView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) {
            newWebView.isInspectable = true
        }
        #endif

        view.addSubview(newWebView)
        NSLayoutConstraint.activate([
            newWebView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            newWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            newWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            newWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        newWebView.loadFileURL(coordinator.indexURL, allowingReadAccessTo: coordinator.webRootURL)
        webView = newWebView
    }

    /// 把最新的账号 / 工作室状态推给页面（同步 window.__nativeState 缓存）
    func pushNativeState(_ json: String) {
        webView?.callPage("window.__setNativeState(JSON.parse(state));", arguments: ["state": json])
    }

    func applyTheme(dark: Bool) {
        isDarkTheme = dark
        // 与页面的 --bg-page 保持一致（浅色 #F4F7FB，深色 #141820），安全区域外不会露出白边
        view.backgroundColor = dark
            ? UIColor(red: 0.078, green: 0.094, blue: 0.125, alpha: 1)
            : UIColor(red: 0.957, green: 0.969, blue: 0.984, alpha: 1)
        view.window?.backgroundColor = view.backgroundColor
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "file" || scheme == "about" || scheme == "blob" || scheme == "data" {
            decisionHandler(.allow)
            return
        }
        // 主界面不应跳转到外部网页：交给系统处理
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        decisionHandler(.cancel)
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        AlertPresenter.show(title: nil, message: message, onConfirm: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        AlertPresenter.show(title: nil, message: message, confirm: "确定", cancel: "取消",
                            onConfirm: { completionHandler(true) }, onCancel: { completionHandler(false) })
    }
}
