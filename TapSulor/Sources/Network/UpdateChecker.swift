import Foundation

/// 检查更新：读取与桌面版相同的 version.json，只使用 ios_* 字段（见 TapTapLogic.updateInfo）。
enum UpdateChecker {
    enum Outcome {
        case failed
        case upToDate
        case available(UpdateInfo)
    }

    static let infoURL = URL(string: "https://ark.yanyususu.online/tapsulor/version.json")!

    static var localVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    static func check() async -> Outcome {
        var request = URLRequest(url: infoURL)
        request.timeoutInterval = 15
        request.setValue("TapSulor/\(localVersion) (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .failed
            }
            if let info = TapTapLogic.updateInfo(from: json, localVersion: localVersion) {
                return .available(info)
            }
            return .upToDate
        } catch {
            return .failed
        }
    }
}
