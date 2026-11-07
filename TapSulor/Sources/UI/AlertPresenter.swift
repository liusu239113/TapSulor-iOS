import Foundation
import UIKit

/// 统一的弹窗工具：总是从最上层的控制器弹出。
@MainActor
enum AlertPresenter {
    static func topViewController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var controller = windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    static func show(title: String?, message: String?, confirm: String = "好", cancel: String? = nil,
                     onConfirm: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let cancel = cancel {
            alert.addAction(UIAlertAction(title: cancel, style: .cancel) { _ in onCancel?() })
        }
        alert.addAction(UIAlertAction(title: confirm, style: .default) { _ in onConfirm?() })
        topViewController()?.present(alert, animated: true)
    }
}
