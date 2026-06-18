import Foundation
import Observation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth

// MARK: - Firestore Service (Cloud Sync for Game State)

@MainActor @Observable
final class FirestoreService {

    // MARK: - State

    var isSyncing = false
    var lastSyncDate: Date?

    // MARK: - Private

    private var db: Firestore { Firestore.firestore() }

    // MARK: - Security Limits

    private enum Limits {
        static let maxArraySize = 500
        static let maxStringLength = 200
        static let maxDisplayNameLength = 100
        static let maxEmailLength = 320
        static let maxInterests = 20
        static let maxPoints = 1_000_000
        static let maxLifetimePoints = 10_000_000
    }

    // MARK: - Sync Game State to Cloud

    /// Upload current game state to Firestore for the given user.
    /// Validates auth + data integrity before writing.
    func syncGameState(
        userID: String,
        collectedPlaceIDs: Set<String>,
        checkedInEventIDs: Set<String>,
        pointsBalance: Int,
        lifetimePoints: Int,
        redeemedRewardIDs: Set<String>
    ) async {
        // Verify the authenticated user matches the target document
        guard let currentUID = Auth.auth().currentUser?.uid, currentUID == userID else {
            print("[FirestoreService] BLOCKED: auth mismatch — refusing to sync for \(userID)")
            return
        }

        // Clamp and sanitize before writing
        let sanitizedCollected = sanitizeIDArray(Array(collectedPlaceIDs), limit: Limits.maxArraySize)
        let sanitizedEvents = sanitizeIDArray(Array(checkedInEventIDs), limit: Limits.maxArraySize)
        let sanitizedRewards = sanitizeIDArray(Array(redeemedRewardIDs), limit: Limits.maxArraySize)
        let clampedPoints = clamp(pointsBalance, min: 0, max: Limits.maxPoints)
        let clampedLifetime = clamp(lifetimePoints, min: 0, max: Limits.maxLifetimePoints)

        isSyncing = true

        do {
            let docRef = db.collection("users").document(userID)
            try await docRef.setData([
                "collectedPlaceIDs": sanitizedCollected,
                "checkedInEventIDs": sanitizedEvents,
                "pointsBalance": clampedPoints,
                "lifetimePoints": clampedLifetime,
                "redeemedRewardIDs": sanitizedRewards,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("[FirestoreService] syncGameState error: \(error.localizedDescription)")
        }

        self.isSyncing = false
        self.lastSyncDate = Date()
    }

    /// Download game state from Firestore for the given user.
    /// Returns nil if no cloud data exists or auth doesn't match.
    func fetchGameState(userID: String) async -> CloudGameState? {
        // Verify the authenticated user matches the target document
        guard let currentUID = Auth.auth().currentUser?.uid, currentUID == userID else {
            print("[FirestoreService] BLOCKED: auth mismatch — refusing to fetch for \(userID)")
            return nil
        }

        isSyncing = true

        do {
            let docRef = db.collection("users").document(userID)
            let snapshot = try await docRef.getDocument()

            guard let data = snapshot.data() else {
                self.isSyncing = false
                return nil
            }

            // Safely extract and validate returned data
            let collectedPlaceIDs = Set(extractStringArray(data["collectedPlaceIDs"], limit: Limits.maxArraySize))
            let checkedInEventIDs = Set(extractStringArray(data["checkedInEventIDs"], limit: Limits.maxArraySize))
            let pointsBalance = clamp(data["pointsBalance"] as? Int ?? 0, min: 0, max: Limits.maxPoints)
            let lifetimePoints = clamp(data["lifetimePoints"] as? Int ?? 0, min: 0, max: Limits.maxLifetimePoints)
            let redeemedRewardIDs = Set(extractStringArray(data["redeemedRewardIDs"], limit: Limits.maxArraySize))

            self.isSyncing = false

            return CloudGameState(
                collectedPlaceIDs: collectedPlaceIDs,
                checkedInEventIDs: checkedInEventIDs,
                pointsBalance: pointsBalance,
                lifetimePoints: lifetimePoints,
                redeemedRewardIDs: redeemedRewardIDs
            )
        } catch {
            print("[FirestoreService] fetchGameState error: \(error.localizedDescription)")
            self.isSyncing = false
            return nil
        }
    }

    /// Save user profile info to Firestore.
    /// Validates auth + sanitizes all string inputs.
    func saveUserProfile(
        userID: String,
        displayName: String,
        email: String,
        interests: [String]
    ) async {
        // Verify the authenticated user matches the target document
        guard let currentUID = Auth.auth().currentUser?.uid, currentUID == userID else {
            print("[FirestoreService] BLOCKED: auth mismatch — refusing to save profile for \(userID)")
            return
        }

        // Sanitize inputs
        let safeName = sanitizeString(displayName, maxLength: Limits.maxDisplayNameLength)
        let safeEmail = sanitizeString(email, maxLength: Limits.maxEmailLength)
        let safeInterests = interests
            .prefix(Limits.maxInterests)
            .map { sanitizeString($0, maxLength: 50) }

        do {
            try await db.collection("users").document(userID).setData([
                "displayName": safeName,
                "email": safeEmail,
                "interests": safeInterests,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("[FirestoreService] saveUserProfile error: \(error.localizedDescription)")
        }
    }

    // MARK: - Sanitization Helpers

    /// Remove control characters, trim whitespace, and enforce max length.
    private func sanitizeString(_ input: String, maxLength: Int) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.unicodeScalars.filter { scalar in
            // Allow printable characters only — strip control chars
            !CharacterSet.controlCharacters.contains(scalar)
        }
        let result = String(String.UnicodeScalarView(cleaned))
        return String(result.prefix(maxLength))
    }

    /// Sanitize an array of ID strings: trim, remove empties, cap length, enforce per-element limit.
    private func sanitizeIDArray(_ input: [String], limit: Int) -> [String] {
        input
            .prefix(limit)
            .map { sanitizeString($0, maxLength: Limits.maxStringLength) }
            .filter { !$0.isEmpty }
    }

    /// Safely extract a string array from Firestore data, with bounds.
    private func extractStringArray(_ value: Any?, limit: Int) -> [String] {
        guard let array = value as? [String] else { return [] }
        return Array(array.prefix(limit))
    }

    /// Clamp an integer to a safe range.
    private func clamp(_ value: Int, min minVal: Int, max maxVal: Int) -> Int {
        Swift.min(Swift.max(value, minVal), maxVal)
    }
}

// MARK: - Cloud Game State

struct CloudGameState {
    let collectedPlaceIDs: Set<String>
    let checkedInEventIDs: Set<String>
    let pointsBalance: Int
    let lifetimePoints: Int
    let redeemedRewardIDs: Set<String>
}
