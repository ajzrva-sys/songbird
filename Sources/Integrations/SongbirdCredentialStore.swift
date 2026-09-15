import Foundation
import LocalAuthentication
import Security

public enum SongbirdCredential: String, CaseIterable, Sendable {
    case lastFMAPIKey
    case lastFMAPISecret
    case lastFMSessionKey
    case discogsToken

    fileprivate var service: String {
        switch self {
        case .lastFMAPIKey, .lastFMAPISecret, .lastFMSessionKey:
            return "com.songbird.lastfm"
        case .discogsToken:
            return "com.songbird.discogs"
        }
    }

    fileprivate var account: String {
        switch self {
        case .lastFMAPIKey: return "api_key"
        case .lastFMAPISecret: return "api_secret"
        case .lastFMSessionKey: return "session_key"
        case .discogsToken: return "personal_access_token"
        }
    }
}

public enum SongbirdCredentialKeychainMode: Equatable, Sendable {
    case dataProtection
    case fileBased

    /// The data-protection Keychain requires an access group supplied by a
    /// provisioning-authorized signing entitlement. Local ad-hoc packages do
    /// not have one and must use the user's encrypted login Keychain instead.
    public static var currentProcess: SongbirdCredentialKeychainMode {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &dynamicCode) == errSecSuccess,
              let dynamicCode else {
            return .fileBased
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return .fileBased
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
              let information = signingInformation as? [String: Any],
              let entitlements = information[kSecCodeInfoEntitlementsDict as String]
                as? [String: Any] else {
            return .fileBased
        }
        return resolved(from: entitlements)
    }

    static func resolved(from entitlements: [String: Any]?) -> SongbirdCredentialKeychainMode {
        guard let entitlements else { return .fileBased }
        if let identifier = entitlements["com.apple.application-identifier"] as? String,
           identifier.isEmpty == false {
            return .dataProtection
        }
        let accessGroupKeys = ["keychain-access-groups", "com.apple.security.keychain-access-groups"]
        if accessGroupKeys.contains(where: {
            (entitlements[$0] as? [String])?.isEmpty == false
        }) {
            return .dataProtection
        }
        return .fileBased
    }

    fileprivate var usesDataProtection: Bool {
        self == .dataProtection
    }
}

public enum SongbirdCredentialStoreError: Error, LocalizedError, Equatable, Sendable {
    case encodingFailed
    case decodingFailed
    case interactionNotAllowed
    case missingEntitlement
    case unexpectedStatus(operation: String, status: Int32)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "The credential could not be encoded."
        case .decodingFailed:
            return "The saved credential could not be decoded."
        case .interactionNotAllowed:
            return "The Keychain is locked. Unlock the Mac and try again."
        case .missingEntitlement:
            return "This copy of Songbird is not signed for the data-protection Keychain."
        case .unexpectedStatus(let operation, let status):
            let systemMessage = SecCopyErrorMessageString(OSStatus(status), nil) as String?
            return "Keychain \(operation) failed (\(status)): \(systemMessage ?? "Unknown error")"
        case .verificationFailed:
            return "The credential could not be verified after saving."
        }
    }
}

public protocol SongbirdCredentialStoring: Sendable {
    func value(
        for credential: SongbirdCredential,
        interaction: SongbirdCredentialInteractionPolicy
    ) async throws -> String?
    func setValue(_ value: String, for credential: SongbirdCredential) async throws
    func removeValue(for credential: SongbirdCredential) async throws
}

public enum SongbirdCredentialInteractionPolicy: Equatable, Sendable {
    case allowAuthenticationUI
    case failIfAuthenticationRequired
}

public extension SongbirdCredentialStoring {
    func value(for credential: SongbirdCredential) async throws -> String? {
        try await value(for: credential, interaction: .allowAuthenticationUI)
    }
}

/// Serializes Security framework access away from the main actor.
public actor SongbirdCredentialStore: SongbirdCredentialStoring {
    public static let shared = SongbirdCredentialStore()
    private var keychainMode: SongbirdCredentialKeychainMode
    private var cachedValues: [SongbirdCredential: String] = [:]
    private var knownMissing: Set<SongbirdCredential> = []

    public init(keychainMode: SongbirdCredentialKeychainMode = .currentProcess) {
        self.keychainMode = keychainMode
    }

    static func authenticationContext(
        for interaction: SongbirdCredentialInteractionPolicy
    ) -> LAContext? {
        guard interaction == .failIfAuthenticationRequired else { return nil }
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    public func value(for credential: SongbirdCredential) throws -> String? {
        try value(for: credential, interaction: .allowAuthenticationUI)
    }

    public func value(
        for credential: SongbirdCredential,
        interaction: SongbirdCredentialInteractionPolicy
    ) throws -> String? {
        if let cached = cachedValues[credential] { return cached }
        if knownMissing.contains(credential) { return nil }

        do {
            let stored = try value(
                for: credential,
                mode: keychainMode,
                interaction: interaction
            )
            cache(stored, for: credential)
            return stored
        } catch SongbirdCredentialStoreError.missingEntitlement
            where keychainMode == .dataProtection {
            keychainMode = .fileBased
            let stored = try value(
                for: credential,
                mode: .fileBased,
                interaction: interaction
            )
            cache(stored, for: credential)
            return stored
        }
    }

    public func setValue(_ value: String, for credential: SongbirdCredential) throws {
        guard let data = value.data(using: .utf8) else {
            throw SongbirdCredentialStoreError.encodingFailed
        }

        do {
            try write(data, for: credential, mode: keychainMode)
        } catch SongbirdCredentialStoreError.missingEntitlement
            where keychainMode == .dataProtection {
            keychainMode = .fileBased
            try write(data, for: credential, mode: .fileBased)
        }
        cache(value, for: credential)
    }

    public func removeValue(for credential: SongbirdCredential) throws {
        do {
            try removeValue(for: credential, mode: keychainMode)
        } catch SongbirdCredentialStoreError.missingEntitlement
            where keychainMode == .dataProtection {
            keychainMode = .fileBased
            try removeValue(for: credential, mode: .fileBased)
        }
        cache(nil, for: credential)
    }

    /// Writes missing values, verifies every supplied value, and leaves the
    /// source untouched if any Keychain operation fails.
    public func migrateLegacyValues(_ values: [SongbirdCredential: String]) throws {
        var newlyWritten = Set<SongbirdCredential>()
        for (credential, legacyValue) in values where legacyValue.isEmpty == false {
            if try value(for: credential) == nil {
                try setValue(legacyValue, for: credential)
                newlyWritten.insert(credential)
            }
        }
        for (credential, legacyValue) in values where legacyValue.isEmpty == false {
            guard let stored = try value(for: credential), stored.isEmpty == false else {
                throw SongbirdCredentialStoreError.verificationFailed
            }
            if newlyWritten.contains(credential), stored != legacyValue {
                throw SongbirdCredentialStoreError.verificationFailed
            }
        }
    }

    private func value(
        for credential: SongbirdCredential,
        mode: SongbirdCredentialKeychainMode,
        interaction: SongbirdCredentialInteractionPolicy
    ) throws -> String? {
        if let stored = try read(
            credential,
            dataProtection: mode.usesDataProtection,
            interaction: interaction
        ) {
            return stored
        }
        guard mode == .dataProtection,
              let legacy = try read(
                  credential,
                  dataProtection: false,
                  interaction: interaction
              ) else {
            return nil
        }

        guard let data = legacy.data(using: .utf8) else {
            throw SongbirdCredentialStoreError.encodingFailed
        }
        try write(data, for: credential, mode: .dataProtection)
        guard try read(
            credential,
            dataProtection: true,
            interaction: interaction
        ) == legacy else {
            throw SongbirdCredentialStoreError.verificationFailed
        }
        let status = SecItemDelete(
            baseQuery(for: credential, dataProtection: false) as CFDictionary
        )
        try check(status, operation: "legacy delete", missingIsSuccess: true)
        return legacy
    }

    private func write(
        _ data: Data,
        for credential: SongbirdCredential,
        mode: SongbirdCredentialKeychainMode
    ) throws {
        let dataProtection = mode.usesDataProtection

        var add = baseQuery(for: credential, dataProtection: dataProtection)
        add[kSecValueData] = data
        if dataProtection {
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = SecItemAdd(add as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            var updates: [CFString: Any] = [kSecValueData: data]
            if dataProtection {
                updates[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            let updateStatus = SecItemUpdate(
                baseQuery(for: credential, dataProtection: dataProtection) as CFDictionary,
                updates as CFDictionary
            )
            try check(updateStatus, operation: "update", missingIsSuccess: false)
        case errSecInteractionNotAllowed:
            throw SongbirdCredentialStoreError.interactionNotAllowed
        case errSecMissingEntitlement:
            throw SongbirdCredentialStoreError.missingEntitlement
        default:
            throw SongbirdCredentialStoreError.unexpectedStatus(
                operation: "save",
                status: status
            )
        }
    }

    private func removeValue(
        for credential: SongbirdCredential,
        mode: SongbirdCredentialKeychainMode
    ) throws {
        let status = SecItemDelete(
            baseQuery(for: credential, dataProtection: mode.usesDataProtection) as CFDictionary
        )
        try check(status, operation: "delete", missingIsSuccess: true)
        if mode == .dataProtection {
            let legacyStatus = SecItemDelete(
                baseQuery(for: credential, dataProtection: false) as CFDictionary
            )
            try check(legacyStatus, operation: "legacy delete", missingIsSuccess: true)
        }
    }

    private func read(
        _ credential: SongbirdCredential,
        dataProtection: Bool,
        interaction: SongbirdCredentialInteractionPolicy = .allowAuthenticationUI
    ) throws -> String? {
        var query = baseQuery(for: credential, dataProtection: dataProtection)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        if let context = Self.authenticationContext(for: interaction) {
            query[kSecUseAuthenticationContext] = context
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw SongbirdCredentialStoreError.decodingFailed
            }
            return value
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw SongbirdCredentialStoreError.interactionNotAllowed
        case errSecMissingEntitlement:
            throw SongbirdCredentialStoreError.missingEntitlement
        default:
            throw SongbirdCredentialStoreError.unexpectedStatus(
                operation: "read",
                status: status
            )
        }
    }

    private func baseQuery(
        for credential: SongbirdCredential,
        dataProtection: Bool
    ) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: credential.service,
            kSecAttrAccount: credential.account,
            kSecUseDataProtectionKeychain: dataProtection,
        ]
    }

    private func check(
        _ status: OSStatus,
        operation: String,
        missingIsSuccess: Bool
    ) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound where missingIsSuccess:
            return
        case errSecInteractionNotAllowed:
            throw SongbirdCredentialStoreError.interactionNotAllowed
        case errSecMissingEntitlement:
            throw SongbirdCredentialStoreError.missingEntitlement
        default:
            throw SongbirdCredentialStoreError.unexpectedStatus(
                operation: operation,
                status: status
            )
        }
    }

    private func cache(_ value: String?, for credential: SongbirdCredential) {
        if let value {
            cachedValues[credential] = value
            knownMissing.remove(credential)
        } else {
            cachedValues.removeValue(forKey: credential)
            knownMissing.insert(credential)
        }
    }
}

@MainActor
public enum LastFMCredentialMigration {
    public static func migrateIfNeeded(
        store: any SongbirdCredentialStoring = SongbirdCredentialStore.shared,
        defaults: UserDefaults = .standard
    ) async throws {
        let mappings: [(String, SongbirdCredential)] = [
            (LastFMClient.apiKeyKey, .lastFMAPIKey),
            (LastFMClient.apiSecretKey, .lastFMAPISecret),
            (LastFMClient.sessionKeyKey, .lastFMSessionKey),
        ]
        let pairs: [(SongbirdCredential, String)] = mappings.compactMap { key, credential in
            guard let value = defaults.string(forKey: key), value.isEmpty == false else { return nil }
            return (credential, value)
        }
        let legacy = Dictionary(uniqueKeysWithValues: pairs)
        guard legacy.isEmpty == false else { return }

        for (credential, value) in legacy {
            let existing = try await store.value(for: credential)
            if existing == nil {
                try await store.setValue(value, for: credential)
                guard try await store.value(for: credential) == value else {
                    throw SongbirdCredentialStoreError.verificationFailed
                }
            } else if existing?.isEmpty == true {
                throw SongbirdCredentialStoreError.verificationFailed
            }
        }
        for (key, _) in mappings where defaults.string(forKey: key)?.isEmpty == false {
            defaults.removeObject(forKey: key)
        }
    }
}
