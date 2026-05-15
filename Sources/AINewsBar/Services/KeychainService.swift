import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()

    private let openAIKeyAccount = "openai-api-key"
    private let service = "com.ainewsbar"

    func saveOpenAIKey(_ key: String) {
        save(key, account: openAIKeyAccount)
    }

    func getOpenAIKey() -> String? {
        get(account: openAIKeyAccount)
    }

    func deleteOpenAIKey() {
        delete(account: openAIKeyAccount)
    }

    private func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func get(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
