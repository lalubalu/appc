import Foundation
@preconcurrency import FirebaseFunctions

// MARK: - Functions Service (server-authoritative game actions)
//
// Thin wrapper around the Cloud Functions callables that own ALL point math.
// The client never writes points / check-ins / redemptions to Firestore directly
// (the security rules deny it) — it asks the server and adopts the returned truth.
// See functions/src/index.ts for the matching server code.
//
// Stateless + Sendable: the non-Sendable Firebase payload/result dictionaries are
// created and consumed entirely inside each call, so only Sendable value types
// cross actor boundaries (Swift 6 friendly).

/// Outcome of checkInToEvent / collectPlace.
struct ServerAwardResult: Sendable {
    let alreadyDone: Bool     // idempotent no-op (double check-in / double collect)
    let awarded: Int
    let newBalance: Int?
    let newLifetime: Int?
}

/// Outcome of redeemReward.
struct ServerRedeemResult: Sendable {
    let redeemed: Bool
    let remaining: Int
}

enum ServerCallError: LocalizedError, Sendable {
    case notSignedIn
    case offline
    case alreadyRedeemed
    case notEnoughPoints
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to continue."
        case .offline: return "You appear to be offline. Try again once you're connected."
        case .alreadyRedeemed: return "You've already redeemed this reward."
        case .notEnoughPoints: return "Not enough points yet."
        case .server(let message): return message
        }
    }
}

final class FunctionsService: Sendable {

    init() {}

    // MARK: - Callables

    func checkInToEvent(eventId: String, category: String, claimedPoints: Int) async throws -> ServerAwardResult {
        let data = try await Self.call("checkInToEvent", [
            "eventId": eventId,
            "category": category,
            "claimedPoints": claimedPoints,
        ])
        return ServerAwardResult(
            alreadyDone: data["alreadyCheckedIn"] as? Bool ?? false,
            awarded: data["awarded"] as? Int ?? 0,
            newBalance: data["newBalance"] as? Int,
            newLifetime: data["newLifetime"] as? Int
        )
    }

    func collectPlace(placeId: String, claimedPoints: Int) async throws -> ServerAwardResult {
        let data = try await Self.call("collectPlace", [
            "placeId": placeId,
            "claimedPoints": claimedPoints,
        ])
        return ServerAwardResult(
            alreadyDone: data["alreadyCollected"] as? Bool ?? false,
            awarded: data["awarded"] as? Int ?? 0,
            newBalance: data["newBalance"] as? Int,
            newLifetime: data["newLifetime"] as? Int
        )
    }

    func redeemReward(rewardId: String) async throws -> ServerRedeemResult {
        let data = try await Self.call("redeemReward", ["rewardId": rewardId])
        return ServerRedeemResult(
            redeemed: data["redeemed"] as? Bool ?? false,
            remaining: data["remaining"] as? Int ?? 0
        )
    }

    // MARK: - Plumbing

    /// Runs a callable and returns its result dictionary. Both the payload and the
    /// result dictionary live entirely inside this nonisolated function's region.
    private static func call(_ name: String, _ payload: [String: any Sendable]) async throws -> [String: Any] {
        do {
            let result = try await Functions.functions().httpsCallable(name).call(payload)
            return result.data as? [String: Any] ?? [:]
        } catch let error as NSError {
            throw mapError(error)
        }
    }

    /// Map raw NSErrors from the Functions SDK / URL loading into typed errors.
    private static func mapError(_ error: NSError) -> ServerCallError {
        if error.domain == NSURLErrorDomain { return .offline }
        if error.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: error.code) {
            case .unavailable, .deadlineExceeded, .internal, .notFound:
                // Network-ish / transient — safe to retry later (callables are
                // idempotent). .notFound covers the window where the Functions
                // aren't deployed yet: keep ops queued instead of dropping them.
                return .offline
            case .alreadyExists: return .alreadyRedeemed
            case .failedPrecondition: return .notEnoughPoints
            case .unauthenticated: return .notSignedIn
            default: break
            }
        }
        return .server(error.localizedDescription)
    }
}
