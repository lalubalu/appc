import Foundation
import CoreLocation
import Observation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFunctions

// MARK: - Economy Service — the client's view of the SERVER reward catalog
//
// ONE SOURCE OF TRUTH FOR PRICES.
//
// The app used to carry its own hardcoded reward list. It drifted: the server
// charged 35,000 points for a $5 card (POINTS_PER_DOLLAR = 7000) while the app
// displayed 1,000 — every price on screen was 35x low — and the app browsed
// four tiers the server had deactivated. A comment in SampleData even asserted
// the two were "mirrored", which is how the drift survived review.
//
// Two hardcoded price lists will always drift again. One will not. So the
// server's `listRewardsCatalog` is authoritative for everything that has a
// price or an eligibility rule, and the local catalog survives only as a DEBUG
// offline fallback that a parity test pins to the same arithmetic.
//
// The callable also decides eligibility server-side (which perks this caller
// may see, whether cash is open to them, how much of their rolling ceiling is
// left, whether the treasury kill switch is on) so the client renders honest
// states instead of guessing at rules it cannot enforce.

// MARK: Models

/// A partner perk — the free tier's redemption surface. Costs 500–2,000 points,
/// so it is reachable in a week or two rather than the months a cash card takes.
struct PartnerPerk: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let partner: String
    let description: String?
    let kind: String?
    let pointCost: Int
    /// When set and in the future, this perk is in its Verdure+ early window.
    let earlyAccessUntil: Date?
    /// True when the perk is visible but locked for THIS caller (free user in
    /// the early window). Decided server-side.
    let plusOnlyUntilOpens: Bool
    /// Server's verdict on whether this caller can redeem right now.
    let redeemable: Bool
    let codesLeft: Int
    let terms: String?
    let expiresAt: Date?
    var latitude: Double? = nil
    var longitude: Double? = nil
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    var isSoldOut: Bool { codesLeft <= 0 }

    static func sortedNearby(_ perks: [PartnerPerk], origin: CLLocation?) -> [PartnerPerk] {
        guard let origin else { return perks }
        func distance(_ perk: PartnerPerk) -> Double {
            guard let coordinate = perk.coordinate else { return .infinity }
            return origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        return perks.enumerated().sorted { a, b in
            let left = distance(a.element), right = distance(b.element)
            return left == right ? a.offset < b.offset : left < right
        }.map(\.element)
    }
}

/// A cash gift card. Members-only, and priced at `usd × pointsPerDollar`.
struct CashReward: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let usd: Int
    let cost: Int
    /// Server-side switch. An inactive card must never be browsable at any
    /// balance — advertising one the server refuses is how the paywall came to
    /// sell the $25/$50 tiers that were turned off.
    let active: Bool
}

/// Everything the Rewards screen needs, with this caller's eligibility resolved.
struct RewardsCatalog: Equatable, Sendable {
    var isPlus: Bool = false
    var pointsPerDollar: Int = 7000
    var perks: [PartnerPerk] = []
    var cash: [CashReward] = []
    /// Cash cards are a member benefit; free users see them locked.
    var cashEligible: Bool = false
    var rollingSpentUsd: Int = 0
    var rollingCeilingUsd: Int = 25
    var rollingRemainingUsd: Int = 25
    /// The treasury kill switch. When true no cash redemption will succeed, and
    /// saying so up front beats letting someone spend points into a refusal.
    var treasuryPaused: Bool = false

    /// Only cards the server will actually honour.
    var activeCash: [CashReward] { cash.filter(\.active) }
}

/// A code the member already redeemed (`users/{uid}/perkCodes`).
struct RedeemedPerkCode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let partner: String
    let code: String
    let terms: String?
    let redeemedAt: Date?
    let expiresAt: Date?
}

// MARK: Service

@MainActor @Observable
final class EconomyService {

    private(set) var catalog = RewardsCatalog()
    private(set) var myCodes: [RedeemedPerkCode] = []
    private(set) var isLoading = false
    /// Nil until a load has been attempted. Distinguishes "no perks exist yet"
    /// (an honest, designed empty state) from "we haven't asked yet" (a spinner).
    private(set) var hasLoaded = false
    var lastError: String?

    private var db: Firestore { Firestore.firestore() }

    // MARK: Catalog

    func refresh() async {
        if QAData.offline { hasLoaded = true; return }
        guard Auth.auth().currentUser != nil else { hasLoaded = true; return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let result = try await Functions.functions().httpsCallable("listRewardsCatalog").call([:])
            guard let data = result.data as? [String: Any] else { return }
            catalog = Self.parseCatalog(data)
            lastError = nil
        } catch {
            // Keep whatever we had; the screen shows a retryable state.
            lastError = "Couldn't load rewards. Pull to refresh."
        }
    }

    /// Parsing is separated from the call so it can be unit-tested without a network.
    static func parseCatalog(_ data: [String: Any]) -> RewardsCatalog {
        var c = RewardsCatalog()
        c.isPlus = data["isPlus"] as? Bool ?? false
        c.pointsPerDollar = intValue(data["pointsPerDollar"]) ?? 7000
        c.cashEligible = data["cashEligible"] as? Bool ?? false
        c.rollingSpentUsd = intValue(data["rollingSpentUsd"]) ?? 0
        c.rollingCeilingUsd = intValue(data["rollingCeilingUsd"]) ?? 25
        c.rollingRemainingUsd = intValue(data["rollingRemainingUsd"]) ?? 0
        c.treasuryPaused = data["treasuryPaused"] as? Bool ?? false

        c.perks = (data["perks"] as? [[String: Any]] ?? []).compactMap { p in
            guard let id = p["id"] as? String, !id.isEmpty,
                  let title = p["title"] as? String else { return nil }
            return PartnerPerk(
                id: id,
                title: Sanitize.text(title, max: 80),
                partner: Sanitize.text(p["partner"] as? String, max: 60),
                description: nonEmpty(Sanitize.text(p["description"] as? String, max: 240)),
                kind: p["kind"] as? String,
                pointCost: intValue(p["pointCost"]) ?? 500,
                earlyAccessUntil: msDate(p["earlyAccessUntilMs"]),
                plusOnlyUntilOpens: p["plusOnlyUntilOpens"] as? Bool ?? false,
                redeemable: p["redeemable"] as? Bool ?? false,
                codesLeft: intValue(p["codesLeft"]) ?? 0,
                terms: nonEmpty(Sanitize.text(p["terms"] as? String, max: 240)),
                expiresAt: msDate(p["expiresAtMs"]),
                latitude: p["latitude"] as? Double,
                longitude: p["longitude"] as? Double
            )
        }

        c.cash = (data["cash"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["id"] as? String, !id.isEmpty else { return nil }
            return CashReward(
                id: id,
                name: Sanitize.text(r["name"] as? String, max: 60),
                usd: intValue(r["usd"]) ?? 0,
                cost: intValue(r["cost"]) ?? 0,
                active: r["active"] as? Bool ?? false
            )
        }
        return c
    }

    // MARK: My codes

    /// Reads `users/{uid}/perkCodes` — owner-readable by the rules.
    func loadMyCodes() async {
        if QAData.offline { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("perkCodes").limit(to: 50).getDocuments()
            myCodes = snap.documents.compactMap { doc in
                let d = doc.data()
                guard let code = d["code"] as? String, !code.isEmpty else { return nil }
                return RedeemedPerkCode(
                    id: doc.documentID,
                    title: Sanitize.text(d["title"] as? String, max: 80).ifEmpty("Perk"),
                    partner: Sanitize.text(d["partner"] as? String, max: 60),
                    code: Sanitize.text(code, max: 64),
                    terms: Self.nonEmpty(Sanitize.text(d["terms"] as? String, max: 240)),
                    redeemedAt: (d["redeemedAt"] as? Timestamp)?.dateValue(),
                    expiresAt: (d["expiresAt"] as? Timestamp)?.dateValue()
                )
            }
            .sorted { ($0.redeemedAt ?? .distantPast) > ($1.redeemedAt ?? .distantPast) }
        } catch {
            // Non-fatal: My Codes simply stays as it was.
        }
    }

    // MARK: Helpers

    private static func intValue(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }
    private static func msDate(_ v: Any?) -> Date? {
        guard let ms = intValue(v), ms > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }
    private static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}
