import Foundation
import CoreLocation
import UserNotifications
import Observation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

struct LivePartnerRegion: Decodable, Sendable {
    let partnerId: String, perkId: String
    let latitude: Double, longitude: Double, expiresAtMs: Double
}
private struct LivePartnerConsent: Decodable { let eligible: Bool, enabled: Bool }
private struct LivePartnerRegionPage: Decodable { let regions: [LivePartnerRegion] }
private struct LivePartnerAlert: Decodable { let id: String, perkId: String, title: String, body: String }
private struct LivePartnerAlertResponse: Decodable { let alert: LivePartnerAlert? }
private final class LivePartnerResources {
    var listener: ListenerRegistration?
    deinit { listener?.remove() }
}

@MainActor @Observable final class LivePartnerAlerts: NSObject {
    static let shared = LivePartnerAlerts()
    private(set) var eligible = false
    private(set) var enabled = false
    private(set) var authorization = CLAuthorizationStatus.notDetermined
    private(set) var error: String?
    private(set) var monitoredCount = 0
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let resources = LivePartnerResources()
    @ObservationIgnored private var callbacks: LivePartnerDelegate?
    private var account: String?
    private var epoch = UUID()
    private var requestingUpgrade = false
    private var permissionFlowActive = false
    private var pendingEntries: Set<String> = []
    private var regions: [String: LivePartnerRegion] = [:]
    private var notificationIDs: Set<String> = []
    private var refreshRequest = UUID()

    override init() {
        super.init()
        let callback = LivePartnerDelegate(location: { [weak self] location in Task { @MainActor in await self?.received(location) } },
            authorization: { [weak self] status in Task { @MainActor in self?.authorizationChanged(status) } },
            entry: { [weak self] id in Task { @MainActor in self?.entered(id) } },
            failure: { [weak self] in Task { @MainActor in self?.error = "Location alerts are paused. Open the app to try again." } })
        callbacks = callback; manager.delegate = callback
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.allowsBackgroundLocationUpdates = false
        authorization = manager.authorizationStatus
    }
    nonisolated private static func notificationAuthorization() async -> Int {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
    }
    private var localOffKey: String { "livePartnerAlertsLocalOff.\(account ?? "guest")" }
    private var localOff: Bool { UserDefaults.standard.bool(forKey: localOffKey) }
    func connect(_ uid: String?) {
        guard uid != account else { if enabled { resume() }; return }
        stopMonitoring(); resources.listener?.remove(); resources.listener = nil
        epoch = UUID(); refreshRequest = UUID(); account = uid; eligible = false; enabled = false; error = nil; permissionFlowActive = false
        guard let uid else { return }
        let session = epoch
        resources.listener = Firestore.firestore().document("users/\(uid)").addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, _ in
            guard let snapshot, !snapshot.metadata.isFromCache else { return }
            let data = snapshot.data(), prefs = data?["notificationPrefs"] as? [String: Any]
            let adult = data?["ageBand"] as? String == "adult" && data?["suspended"] as? Bool != true
            let consent = prefs?["livePartnerAlerts"] as? Bool == true && prefs?["livePartnerConsentVersion"] as? String == "live-deals-v1"
            Task { @MainActor [weak self] in
                guard let self, self.epoch == session, self.account == uid, Auth.auth().currentUser?.uid == uid else { return }
                self.eligible = adult; self.enabled = adult && consent && !self.localOff
                if self.enabled { self.resume() } else { self.stopMonitoring() }
                if self.localOff && consent { await self.saveConsent(false) }
            }
        }
    }
    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { connect(nil); return }
        connect(uid)
        let session = epoch
        do {
            let consent = try await PlaceStoryAPI.call("getLivePartnerConsent", [:], as: LivePartnerConsent.self)
            guard account == uid, epoch == session, Auth.auth().currentUser?.uid == uid else { return }
            eligible = consent.eligible; enabled = consent.enabled && !localOff
            if enabled { resume() } else { stopMonitoring() }
        } catch { if account == uid, epoch == session { self.error = "Couldn't load location-alert consent." } }
    }
    /// The only caller is the explicit in-app promotional consent sheet.
    func optIn() async {
        guard eligible, let uid = account, uid == Auth.auth().currentUser?.uid else { return }
        let session = epoch
        requestingUpgrade = false; permissionFlowActive = true
        let wasOff = localOff
        UserDefaults.standard.set(false, forKey: localOffKey)
        if await saveConsent(true) {
            let status = await Self.notificationAuthorization()
            guard epoch == session, account == uid, Auth.auth().currentUser?.uid == uid, eligible, !localOff else { return }
            if status == UNAuthorizationStatus.notDetermined.rawValue {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            }
            NotificationManager.shared.refreshPermissionStatus()
            guard epoch == session, account == uid, Auth.auth().currentUser?.uid == uid, eligible, !localOff else { return }
            enabled = true; resume(requestPermissions: true)
        } else { UserDefaults.standard.set(wasOff, forKey: localOffKey); permissionFlowActive = false }
    }
    func optOut() async {
        UserDefaults.standard.set(true, forKey: localOffKey)
        enabled = false; permissionFlowActive = false; stopMonitoring()
        await saveConsent(false)
    }
    @discardableResult private func saveConsent(_ on: Bool) async -> Bool {
        guard let uid = account, uid == Auth.auth().currentUser?.uid else { return false }
        let session = epoch
        do {
            let response = try await PlaceStoryAPI.call("setLivePartnerConsent", ["enabled": on, "promotionalConsent": on], as: LivePartnerConsent.self)
            guard account == uid, epoch == session, Auth.auth().currentUser?.uid == uid else { return false }
            eligible = response.eligible; error = nil; return true
        } catch { if epoch == session { self.error = on ? "Couldn't enable alerts. Check your connection." : "Alerts stopped on this phone. Reconnect to save the opt-out to your account." }; return false }
    }
    private func resume(requestPermissions: Bool = false) {
        guard enabled, eligible, account == Auth.auth().currentUser?.uid else { stopMonitoring(); return }
        authorization = manager.authorizationStatus
        guard authorization == .authorizedAlways else {
            stopMonitoring()
            if requestPermissions {
                if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
                else if authorization == .authorizedWhenInUse { requestingUpgrade = true; manager.requestAlwaysAuthorization() }
            }
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self), CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            error = "This device doesn't support background location alerts."; return
        }
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation() // One fix; this feature never starts continuous GPS.
    }
    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorization = status
        guard enabled else { stopMonitoring(); return }
        if status == .authorizedWhenInUse, permissionFlowActive, !requestingUpgrade {
            // Reached only after explicit consent and the in-flow When In Use prompt.
            requestingUpgrade = true; manager.requestAlwaysAuthorization()
        } else if status == .authorizedAlways { permissionFlowActive = false; resume() }
        else { stopMonitoring() }
    }
    private func stopMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        for region in manager.monitoredRegions where region.identifier.hasPrefix("verdure-live:") { manager.stopMonitoring(for: region) }
        monitoredCount = 0; regions = [:]; pendingEntries = []; refreshRequest = UUID()
        if !notificationIDs.isEmpty { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(notificationIDs)); notificationIDs = [] }
    }
    private func entered(_ identifier: String) {
        guard enabled, eligible, authorization == .authorizedAlways, regions[identifier] != nil else { return }
        pendingEntries.insert(identifier); manager.requestLocation()
    }
    private func received(_ location: CLLocation) async {
        guard enabled, eligible, authorization == .authorizedAlways, let uid = account, uid == Auth.auth().currentUser?.uid,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100, abs(location.timestamp.timeIntervalSinceNow) <= 60 else { return }
        let session = epoch, entries = pendingEntries.compactMap { regions[$0] }; pendingEntries = []
        for region in entries where region.expiresAtMs > Date().timeIntervalSince1970 * 1000 {
            let center = UNUserNotificationCenter.current(), status = await Self.notificationAuthorization()
            guard status == UNAuthorizationStatus.authorized.rawValue || status == UNAuthorizationStatus.provisional.rawValue else { continue }
            do {
                let result = try await PlaceStoryAPI.call("livePartnerEntry", ["perkId": region.perkId,
                    "lat": location.coordinate.latitude, "lng": location.coordinate.longitude, "accuracy": location.horizontalAccuracy,
                    "sampleAtMs": location.timestamp.timeIntervalSince1970 * 1000], as: LivePartnerAlertResponse.self)
                guard epoch == session, enabled, account == uid, Auth.auth().currentUser?.uid == uid, let alert = result.alert else { continue }
                let content = UNMutableNotificationContent(); content.title = alert.title; content.body = alert.body
                content.userInfo = ["kind": "live-partner", "perkId": alert.perkId, "sponsored": true]; content.sound = .default
                let identifier = "verdure-live-alert:\(alert.id)"; notificationIDs.insert(identifier)
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            } catch { if epoch == session { self.error = "A nearby alert couldn't be delivered." } }
        }
        let token = UUID(); refreshRequest = token
        do {
            let page = try await PlaceStoryAPI.call("livePartnerRegions", ["lat": location.coordinate.latitude, "lng": location.coordinate.longitude], as: LivePartnerRegionPage.self)
            guard epoch == session, refreshRequest == token, enabled, account == uid, Auth.auth().currentUser?.uid == uid else { return }
            let available = max(0, 20 - manager.monitoredRegions.filter { !$0.identifier.hasPrefix("verdure-live:") }.count)
            let chosen = page.regions.prefix(available)
            let next = Dictionary(uniqueKeysWithValues: chosen.map { ("verdure-live:\($0.partnerId)", $0) })
            for region in manager.monitoredRegions where region.identifier.hasPrefix("verdure-live:") && next[region.identifier] == nil { manager.stopMonitoring(for: region) }
            for (id, place) in next {
                let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
                if let existing = manager.monitoredRegions.first(where: { $0.identifier == id }) as? CLCircularRegion,
                   existing.center.latitude == coordinate.latitude, existing.center.longitude == coordinate.longitude { continue }
                if let existing = manager.monitoredRegions.first(where: { $0.identifier == id }) { manager.stopMonitoring(for: existing) }
                let region = CLCircularRegion(center: coordinate, radius: min(400, manager.maximumRegionMonitoringDistance), identifier: id)
                region.notifyOnEntry = true; region.notifyOnExit = false; manager.startMonitoring(for: region)
            }
            regions = next; monitoredCount = next.count; error = nil
        } catch { if epoch == session { self.error = "Nearby regions couldn't refresh." } }
    }
}

private final class LivePartnerDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    let location: (CLLocation) -> Void
    let authorization: (CLAuthorizationStatus) -> Void
    let entry: (String) -> Void
    let failure: () -> Void
    init(location: @escaping (CLLocation) -> Void, authorization: @escaping (CLAuthorizationStatus) -> Void,
         entry: @escaping (String) -> Void, failure: @escaping () -> Void) {
        self.location = location; self.authorization = authorization; self.entry = entry; self.failure = failure
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { if let latest = locations.last { location(latest) } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorization(manager.authorizationStatus) }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { entry(region.identifier) }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { failure() }
}
