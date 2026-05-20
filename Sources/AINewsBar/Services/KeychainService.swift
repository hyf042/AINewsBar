import Foundation

// 个人工具无需 Keychain 强安全保证，用 UserDefaults 存储 API Key 避免每次弹授权窗口
final class KeychainService {
    static let shared = KeychainService()

    private let defaults = UserDefaults.standard
    private let apiKeyKey = "com.ainewsbar.claude-api-key"

    func saveAPIKey(_ key: String) {
        defaults.set(key.isEmpty ? nil : key, forKey: apiKeyKey)
    }

    func getAPIKey() -> String? {
        let value = defaults.string(forKey: apiKeyKey)
        return value?.isEmpty == false ? value : nil
    }

    func deleteAPIKey() {
        defaults.removeObject(forKey: apiKeyKey)
    }
}
