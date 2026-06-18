import Foundation
import SwiftUI
import Observation
@preconcurrency import FirebaseAuth

// MARK: - Auth Service (Firebase Auth Wrapper)

@MainActor @Observable
final class AuthService {

    // MARK: - Published State

    var currentUser: ConnectifyUser?
    var isAuthenticated: Bool { currentUser != nil }
    var isLoading = false
    var errorMessage: String?

    // MARK: - Private

    private let userKey = "currentUserJSON"
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Init

    init() {
        listenForAuthChanges()
    }

    // MARK: - Auth State Listener

    private func listenForAuthChanges() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                if let firebaseUser {
                    let user = ConnectifyUser(
                        uid: firebaseUser.uid,
                        email: firebaseUser.email ?? "",
                        displayName: firebaseUser.displayName ?? firebaseUser.email?.components(separatedBy: "@").first ?? "User",
                        joinDate: firebaseUser.metadata.creationDate ?? Date()
                    )
                    self?.currentUser = user
                    self?.persistUser(user)
                } else {
                    self?.currentUser = nil
                }
            }
        }
    }

    // MARK: - Auth Methods

    /// Sign up with email, password, and display name.
    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        errorMessage = nil

        // Sanitize inputs
        let cleanEmail = Self.sanitize(email, maxLength: 320).lowercased()
        let cleanName = Self.sanitize(displayName, maxLength: 100)

        // Validate email format
        guard !cleanEmail.isEmpty, Self.isValidEmail(cleanEmail) else {
            isLoading = false
            errorMessage = "Please enter a valid email address."
            throw AuthError.invalidEmail
        }
        // Validate password strength
        guard password.count >= 6, password.count <= 128 else {
            isLoading = false
            errorMessage = "Password must be 6–128 characters."
            throw AuthError.weakPassword
        }
        // Validate display name
        guard !cleanName.isEmpty else {
            isLoading = false
            errorMessage = "Please enter your name."
            throw AuthError.missingName
        }

        do {
            let result = try await Auth.auth().createUser(withEmail: cleanEmail, password: password)
            let uid = result.user.uid
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = cleanName
            try await changeRequest.commitChanges()

            let user = ConnectifyUser(
                uid: uid,
                email: cleanEmail,
                displayName: cleanName,
                joinDate: Date()
            )

            self.currentUser = user
            self.isLoading = false
            self.persistUser(user)
        } catch {
            self.isLoading = false
            self.errorMessage = Self.mapFirebaseError(error as NSError)
            throw AuthError.unknown(self.errorMessage ?? error.localizedDescription)
        }
    }

    /// Sign in with email and password.
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        let cleanEmail = Self.sanitize(email, maxLength: 320).lowercased()

        guard !cleanEmail.isEmpty, Self.isValidEmail(cleanEmail) else {
            isLoading = false
            errorMessage = "Please enter a valid email address."
            throw AuthError.invalidEmail
        }
        guard !password.isEmpty, password.count <= 128 else {
            isLoading = false
            errorMessage = "Please enter your password."
            throw AuthError.emptyPassword
        }

        do {
            let result = try await Auth.auth().signIn(withEmail: cleanEmail, password: password)
            let firebaseUser = result.user
            let uid = firebaseUser.uid
            let userEmail = firebaseUser.email ?? email
            let name = firebaseUser.displayName ?? email.components(separatedBy: "@").first ?? "User"
            let created = firebaseUser.metadata.creationDate ?? Date()

            let user = ConnectifyUser(
                uid: uid,
                email: userEmail,
                displayName: name,
                joinDate: created
            )

            self.currentUser = user
            self.isLoading = false
            self.persistUser(user)
        } catch {
            self.isLoading = false
            self.errorMessage = Self.mapFirebaseError(error as NSError)
            throw AuthError.unknown(self.errorMessage ?? error.localizedDescription)
        }
    }

    /// Sign out the current user.
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
        }

        currentUser = nil
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    /// Clear any displayed error.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Firebase Error Mapping

    private static func mapFirebaseError(_ error: NSError) -> String {
        switch error.code {
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "An account with this email already exists."
        case AuthErrorCode.invalidEmail.rawValue:
            return "Invalid email address."
        case AuthErrorCode.weakPassword.rawValue:
            return "Password is too weak. Use at least 6 characters."
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email."
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password."
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Please check your connection."
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Please try again later."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Input Sanitization

    /// Strip control characters, trim whitespace, enforce max length.
    private static func sanitize(_ input: String, maxLength: Int) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        let result = String(String.UnicodeScalarView(cleaned))
        return String(result.prefix(maxLength))
    }

    /// Validate email format using a strict regex.
    private static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Session Persistence (local backup)

    private func persistUser(_ user: ConnectifyUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }
}

// MARK: - User Model

struct ConnectifyUser: Codable, Identifiable {
    let uid: String
    let email: String
    let displayName: String
    let joinDate: Date

    var id: String { uid }

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var joinDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: joinDate)
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case missingName
    case emptyPassword
    case networkError
    case userNotFound
    case wrongPassword
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Invalid email address."
        case .weakPassword: return "Password must be at least 6 characters."
        case .missingName: return "Please enter your name."
        case .emptyPassword: return "Please enter your password."
        case .networkError: return "Network error. Please try again."
        case .userNotFound: return "No account found with this email."
        case .wrongPassword: return "Incorrect password."
        case .unknown(let msg): return msg
        }
    }
}
