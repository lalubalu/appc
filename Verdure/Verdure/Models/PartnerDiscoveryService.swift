import SwiftUI
import CoreLocation
import Observation
@preconcurrency import FirebaseFunctions
@preconcurrency import FirebaseAuth

struct PartnerMapOffer: Identifiable, Equatable {
    let id: String
    let partnerID: String
    let partner: String
    let title: String
    let description: String
    let pointCost: Int
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let walkingMinutes: Int
    let claimable: Bool
    let opensAt: Date?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    static func parse(_ data: [String: Any]) -> PartnerMapOffer? {
        guard let id = data["perkId"] as? String, let partnerID = data["partnerId"] as? String,
              let latitude = data["latitude"] as? Double, let longitude = data["longitude"] as? Double,
              latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return .init(id: id, partnerID: partnerID,
                     partner: Sanitize.text(data["partner"] as? String, max: 60),
                     title: Sanitize.text(data["title"] as? String, max: 80),
                     description: Sanitize.text(data["description"] as? String, max: 200),
                     pointCost: data["pointCost"] as? Int ?? 0, latitude: latitude, longitude: longitude,
                     distanceMeters: data["distanceMeters"] as? Double ?? 0,
                     walkingMinutes: data["walkingMinutes"] as? Int ?? 1,
                     claimable: data["claimable"] as? Bool ?? false,
                     opensAt: (data["earlyAccessUntilMs"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) })
    }
}

@MainActor @Observable
final class PartnerDiscoveryService {
    private(set) var offers: [PartnerMapOffer] = []
    private(set) var nearYou: PartnerMapOffer?
    private(set) var layerEnabled = true
    private(set) var error: String?
    private var uid: String?
    private var sessionID = UUID().uuidString
    private var shownNearYou = false
    private var lastRequest = ""
    private var dismissed = Set<String>()
    private var nearYouExpiresAt = Date.distantPast
    private var expiryTask: Task<Void, Never>?

    func beginSession() {
        sessionID = UUID().uuidString
        shownNearYou = false
        nearYou = nil
        expiryTask?.cancel()
        lastRequest = ""
    }

    func setLayerEnabled(_ enabled: Bool) {
        layerEnabled = enabled
        if let uid { UserDefaults.standard.set(enabled, forKey: "partnerMapLayer.\(uid)") }
    }

    func refresh(around origin: CLLocation?) async {
        let current = Auth.auth().currentUser?.uid
        if current != uid {
            uid = current; offers = []; nearYou = nil; dismissed = []; lastRequest = ""
            sessionID = UUID().uuidString; shownNearYou = false
            if let uid, UserDefaults.standard.object(forKey: "partnerMapLayer.\(uid)") != nil {
                layerEnabled = UserDefaults.standard.bool(forKey: "partnerMapLayer.\(uid)")
            } else { layerEnabled = true }
        }
        guard let current, let origin else { offers = []; nearYou = nil; return }
        if Date() >= nearYouExpiresAt { nearYou = nil }
        let key = "\(current):\(Int(origin.coordinate.latitude * 1000)):\(Int(origin.coordinate.longitude * 1000)):\(Int(Date().timeIntervalSince1970 / 3600))"
        guard key != lastRequest else { return }
        lastRequest = key
        do {
            let map = try await Functions.functions().httpsCallable("nearbyPartners").call([
                "lat": origin.coordinate.latitude, "lng": origin.coordinate.longitude,
                "sessionId": sessionID, "surface": "map"])
            guard uid == current else { return }
            let data = map.data as? [String: Any] ?? [:]
            offers = (data["offers"] as? [[String: Any]] ?? []).compactMap(PartnerMapOffer.parse)
                .filter { !dismissed.contains($0.id) }
            // A cached card ceases to be eligible immediately when it becomes
            // too far away or its live perk disappears. Never substitute a far offer.
            if let card = nearYou, !offers.contains(where: { $0.id == card.id }) ||
                origin.distance(from: CLLocation(latitude: card.latitude, longitude: card.longitude)) > 800 { nearYou = nil }
            if !shownNearYou {
                let result = try await Functions.functions().httpsCallable("nearbyPartners").call([
                    "lat": origin.coordinate.latitude, "lng": origin.coordinate.longitude,
                    "sessionId": sessionID, "surface": "near_you"])
                guard uid == current else { return }
                let payload = result.data as? [String: Any] ?? [:]
                nearYou = (payload["offers"] as? [[String: Any]] ?? []).compactMap(PartnerMapOffer.parse).first
                nearYouExpiresAt = Date(timeIntervalSince1970: (payload["validUntilMs"] as? Double ?? 0) / 1000)
                expiryTask?.cancel()
                let seconds = max(0, nearYouExpiresAt.timeIntervalSinceNow)
                expiryTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) }
                    catch { return }
                    self?.nearYou = nil
                }
                shownNearYou = nearYou != nil
            }
            error = nil
        } catch {
            guard uid == current else { return }
            offers = []; nearYou = nil; lastRequest = ""
            self.error = "Partner offers couldn't refresh."
        }
    }

    func dismiss(_ offer: PartnerMapOffer) async {
        let account = Auth.auth().currentUser?.uid
        do {
            _ = try await Functions.functions().httpsCallable("dismissPerk").call(["perkId": offer.id])
            guard account == Auth.auth().currentUser?.uid, account == uid else { return }
            dismissed.insert(offer.id); offers.removeAll { $0.id == offer.id }
            if nearYou?.id == offer.id { nearYou = nil }
            error = nil
            Analytics.log(event: .perkDismissed, params: ["perkId": offer.id])
        } catch { self.error = "Couldn't remember that dismissal. Try again." }
    }
}
