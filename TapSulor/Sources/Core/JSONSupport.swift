import Foundation

extension Optional where Wrapped == String {
    /// 放进 JSON 字典时：nil 变成 NSNull（JavaScript 里的 null）
    var jsonValue: Any {
        if let value = self {
            return value
        }
        return NSNull()
    }
}

enum JSONSupport {
    /// 把 JSON 对象转成字符串（传给页面后由 JSON.parse 还原）
    static func string(from object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return "null"
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// 把 Encodable 值转成可放进 JSON 字典的对象（保持与 accounts.json 相同的字段名）
    static func object<T: Encodable>(from value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return NSNull()
        }
        return object
    }
}
