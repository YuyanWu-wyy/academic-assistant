import Foundation
import Security

enum KeyStore {
    static let service = "io.github.YuyanWu-wyy.AcademicAssistant"
    static let account = "deepseek-api-key"
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw AssistantFailure(message: "无法读取钥匙串中的密钥，请重新打开设置。")
        }
        return key
    }
    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrLabel as String] = "学术助手 · DeepSeek API Key"
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else {
                throw AssistantFailure(message: "密钥未能存入钥匙串，请重试。")
            }
        } else if update != errSecSuccess {
            throw AssistantFailure(message: "密钥更新失败，请重试。")
        }
    }
}
