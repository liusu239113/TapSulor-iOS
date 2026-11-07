import Foundation
import UIKit
import WebKit

/// 弹出的网页窗口，用于 TapTap 登录（developer.taptap.cn）与游戏后台（maker.taptap.cn）。
@MainActor
final class WebSheetViewController: UIViewController, WKNavigationDelegate, WKUIDelegate,
                                    UIAdaptivePresentationControllerDelegate {
    let webView: WKWebView
    /// 页面加载完成或地址变化时回调
    var onPageChanged: (@MainActor (URL) -> Void)?
    /// 用户通过按钮或下滑关闭窗口时回调（只触发一次）
    var onClosed: (@MainActor () -> Void)?

    private let startURL: URL
    private var closeNotified = false
    private var urlObservation: NSKeyValueObservation?


    #if DEBUG
    deinit {
        NSLog("[debug] sheet deinit")
    }
    #endif
    init(title: String, url: URL, configuration: WKWebViewConfiguration) {
        self.startURL = url
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("WebSheetViewController 不使用 storyboard")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "关闭", style: .done, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh, target: self, action: #selector(reloadTapped))

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // 单页应用的 history 跳转不会触发 didFinish，所以同时监听 url 变化
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, change in
            guard let url = change.newValue ?? nil else { return }
            Task { @MainActor in
                self?.onPageChanged?(url)
            }
        }

        webView.load(URLRequest(url: startURL))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 下滑关闭时通知调用方
        navigationController?.presentationController?.delegate = self
    }

    @objc private func reloadTapped() {
        webView.reload()
    }

    @objc private func closeTapped() {
        #if DEBUG
        NSLog("[debug] sheet closeTapped")
        #endif
        notifyClosed()
        navigationController?.dismiss(animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        #if DEBUG
        NSLog("[debug] sheet presentationControllerDidDismiss")
        #endif
        notifyClosed()
    }

    private func notifyClosed() {
        guard !closeNotified else { return }
        closeNotified = true
        onClosed?()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        NSLog("[debug] sheet didFinish")
        #endif
        #if DEBUG
        Task { @MainActor in
            let info = await webView.evaluatePage("return document.title + ' | text=' + document.body.innerText.length + ' | html=' + document.documentElement.outerHTML.length + ' | ' + location.href")
            NSLog("[debug] sheet page probe: \(String(describing: info))")
        }
        #endif
        if let url = webView.url {
            onPageChanged?(url)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        #if DEBUG
        NSLog("[debug] sheet decide \(navigationAction.request.url?.absoluteString ?? "nil")")
        #endif
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        if ["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            decisionHandler(.allow)
        } else {
            // weixin://、mqqapi:// 等应用跳转交给系统处理（与桌面版一致）
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
        }
    }

    #if DEBUG
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[debug] sheet provisional fail: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[debug] sheet fail: \(error.localizedDescription)")
    }
    #endif

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // window.open：TapTap 域名留在当前窗口，其它地址交给系统浏览器（与桌面版一致）
        if let url = navigationAction.request.url {
            let host = url.host?.lowercased() ?? ""
            if host.hasSuffix("taptap.cn") || host.hasSuffix("taptap.com") {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
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
