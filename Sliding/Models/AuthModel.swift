//
//  AuthModel.swift
//  Sliding
//

import AuthenticationServices
import Security
import SwiftUI

/// Who you are in the app. Lives on this device for now; a backend will own it later.
nonisolated struct Profile: Codable, Equatable {
    let userID: String
    var displayName: String
    var username: String
}

extension Person {
    /// You, as the rest of the app sees you.
    init(_ profile: Profile) {
        self.init(id: profile.userID, name: profile.displayName, username: profile.username)
    }
}

/// Sign in with Apple and the local profile.
///
/// Apple's user ID is kept in the Keychain. On launch we ask Apple whether that ID is still
/// authorized, and sign out if the user revoked access in Settings.
@Observable
final class AuthModel {
    enum State { case checking, signedOut, needsProfile, signedIn }

    private(set) var state: State = .checking
    private(set) var profile: Profile?
    /// The name Apple shared at first sign-in (it's only ever shared once), used to prefill setup.
    private(set) var suggestedName = ""
    private var userID: String?

    /// Profiles saved on this device, by Apple user ID. Kept across sign-outs, so signing back in
    /// with the same Apple Account goes straight home. (Apple only shares your name the first time.)
    private static let profilesKey = "profiles"

    init() {
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.signOut() }
        }
    }

    /// Restores the session on launch.
    func restore() async {
        await FakeLatency.wait(1.2)
        guard let id = Keychain.read(Self.userIDKey) else { return setState(.signedOut) }
        userID = id
        profile = loadProfile(for: id)

        if !Self.isDebugID(id) {
            // Offline or a temporary error: trust the local session rather than signing out.
            if let credential = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: id),
               credential == .revoked || credential == .notFound {
                return signOut()
            }
        }
        setState(profile == nil ? .needsProfile : .signedIn)
    }

    /// Handles the Sign in with Apple result. Returns a message to show if it failed.
    func handle(_ result: Result<ASAuthorization, Error>) -> String? {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return "Something went wrong signing in. Please try again."
            }
            if let name = credential.fullName {
                suggestedName = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
            }
            begin(userID: credential.user)
            return nil
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return nil }
            return "Couldn't sign in with Apple. Check that you're signed in to your Apple Account in Settings, then try again."
        }
    }

    func saveProfile(displayName: String, username: String) {
        guard let userID else { return }
        let profile = Profile(userID: userID,
                              displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                              username: username.lowercased())
        self.profile = profile
        var all = Self.savedProfiles()
        all[userID] = profile
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
        setState(.signedIn)
    }

    /// Ends the session. The saved profile stays, so signing back in skips setup.
    func signOut() {
        Keychain.delete(Self.userIDKey)
        userID = nil
        profile = nil
        suggestedName = ""
        setState(.signedOut)
    }

    #if DEBUG
    /// Testing aid: a pretend account, for when Sign in with Apple isn't available (e.g. the Simulator).
    func signInForTesting() {
        // A fixed ID, so signing out and skipping again behaves like a returning Apple account.
        begin(userID: "debug-tester")
    }
    #endif

    // MARK: Validation

    /// 3–20 characters: lowercase letters, numbers, dots and underscores.
    static func usernameProblem(_ username: String) -> String? {
        let name = username.lowercased()
        if name.count < 3 { return "At least 3 characters." }
        if name.count > 20 { return "20 characters at most." }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._")
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use letters, numbers, dots and underscores."
        }
        return nil
    }

    // MARK: Private

    private static let userIDKey = "appleUserID"

    private static func isDebugID(_ id: String) -> Bool { id.hasPrefix("debug-") }

    private func begin(userID id: String) {
        Keychain.save(id, for: Self.userIDKey)
        userID = id
        profile = loadProfile(for: id)
        setState(profile == nil ? .needsProfile : .signedIn)
    }

    private func loadProfile(for id: String) -> Profile? {
        Self.savedProfiles()[id]
    }

    private static func savedProfiles() -> [String: Profile] {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([String: Profile].self, from: data) else { return [:] }
        return profiles
    }

    private func setState(_ new: State) {
        withAnimation(.easeInOut(duration: 0.3)) { state = new }
    }
}

/// Minimal Keychain access for small strings, kept on this device only.
private enum Keychain {
    private static let service = "com.shuvamshr.Sliding"

    static func save(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
