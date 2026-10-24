import Foundation
import Security

nonisolated enum APIService: String, CaseIterable, Identifiable {
    case elevenLabs = "ELEVENLABS_API_KEY"
    case anthropic = "ANTHROPIC_API_KEY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .anthropic: "Anthropic (Claude)"
        }
    }
}

/// API keys live in the Keychain, never in the binary. Debug builds also accept them from the launch
/// environment (e.g. `SIMCTL_CHILD_ELEVENLABS_API_KEY`) and copy them into the Keychain on first use.
nonisolated enum APIKeys {
    private static let keychainService = "com.mdawes.pinguo.api-keys"

    static func key(for service: APIService) -> String? {
        if let stored = read(service), !stored.isEmpty { return stored }
        #if DEBUG
        if let fromEnvironment = ProcessInfo.processInfo.environment[service.rawValue], !fromEnvironment.isEmpty {
            save(fromEnvironment, for: service)
            return fromEnvironment
        }
        #endif
        return nil
    }

    static func hasKey(for service: APIService) -> Bool {
        key(for: service) != nil
    }

    static func save(_ value: String, for service: APIService) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        delete(service)
        guard !trimmed.isEmpty else { return }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(_ service: APIService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func read(_ service: APIService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
