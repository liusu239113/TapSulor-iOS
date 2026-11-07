import Foundation
import WebKit

extension WKWebView {
    /// 在页面里执行一段函数体。参数以变量形式传入，不需要手工转义字符串。
    func callPage(_ functionBody: String, arguments: [String: Any] = [:]) {
        callAsyncJavaScript(functionBody, arguments: arguments, in: nil, in: .page) { result in
            if case .failure(let error) = result {
                NSLog("[bridge] 页面调用失败：\(error.localizedDescription)")
            }
        }
    }

    /// 等待页面里的异步函数返回值；失败时返回 nil。
    func evaluatePage(_ functionBody: String) async -> Any? {
        await withCheckedContinuation { continuation in
            callAsyncJavaScript(functionBody, arguments: [:], in: nil, in: .page) { result in
                if case .success(let value) = result {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// JS -> Swift 消息入口（window.webkit.messageHandlers.tapsulor）。只负责解析并转交给 AppCoordinator。
@MainActor
final class WebBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "tapsulor"

    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return }
        coordinator?.handleBridge(op: op, body: body, webView: message.webView)
    }
}
