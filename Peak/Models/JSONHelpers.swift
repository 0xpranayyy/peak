import Foundation

enum JSONStringDecoding {
    /// Gamma often returns arrays as JSON-encoded strings (e.g. `"[\"Yes\",\"No\"]"`).
    static func stringArray(from value: String?) -> [String] {
        guard let value, let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func doubleArray(from value: String?) -> [Double] {
        stringArray(from: value).compactMap(Double.init)
    }

    /// Handles either a JSON string or an already-decoded array of strings/numbers.
    static func flexibleStringArray(from any: Any?) -> [String] {
        switch any {
        case let s as String:
            return stringArray(from: s)
        case let arr as [String]:
            return arr
        case let arr as [Any]:
            return arr.map { "\($0)" }
        default:
            return []
        }
    }

    static func flexibleDoubleArray(from any: Any?) -> [Double] {
        flexibleStringArray(from: any).compactMap(Double.init)
    }
}

extension KeyedDecodingContainer {
    func decodeJSONStringArray(forKey key: Key) -> [String] {
        if let arr = try? decode([String].self, forKey: key) { return arr }
        if let s = try? decode(String.self, forKey: key) { return JSONStringDecoding.stringArray(from: s) }
        return []
    }

    func decodeJSONDoubleArray(forKey key: Key) -> [Double] {
        if let arr = try? decode([Double].self, forKey: key) { return arr }
        if let arr = try? decode([String].self, forKey: key) { return arr.compactMap(Double.init) }
        if let s = try? decode(String.self, forKey: key) { return JSONStringDecoding.doubleArray(from: s) }
        return []
    }

    func decodeFlexibleString(forKey key: Key) -> String? {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) { return String(Int(d)) }
        return nil
    }
}
