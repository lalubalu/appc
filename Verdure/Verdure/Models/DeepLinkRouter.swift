import SwiftUI
import Observation

// MARK: - Deep link routing
//
// A tapped notification must land on the thing it advertised. Anything else —
// dumping the user on the home tab and making them find it — teaches them that
// opening a push is a waste of time, which is how a notification channel dies.
//
// THE COLD-LAUNCH CASE IS THE ONE THAT BREAKS.
//
// When the app is already running, the tap arrives and some view is listening.
// When the app is NOT running, iOS launches it and delivers the tap through
// `didReceive response:` before SwiftUI has built a single view — so a router
// that only forwards live events drops exactly the taps that matter most, and
// it does so silently and only on a real device from a cold start, which is
// the hardest configuration to notice in testing.
//
// So this router HOLDS a pending destination rather than broadcasting it. The
// tab view claims it when it appears. If the app was already open the claim is
// immediate; if it was launched by the tap, the destination simply waits.

@MainActor
@Observable
final class DeepLinkRouter {

    static let shared = DeepLinkRouter()

    enum Destination: Equatable {
        case event(id: String)
        case perk(id: String)
        case rewards
        case notifications
    }

    /// Set by a tap, cleared by whoever handles it.
    private(set) var pending: Destination?

    // Deliberately no tab mapping here. MainTabView owns AppTab and does the
    // switch itself; a duplicate index table in this file would be a second
    // source of truth for tab order that nothing would keep in step.

    func handle(_ destination: Destination) {
        pending = destination
    }

    /// Take the pending destination, if any. Idempotent — a second caller gets
    /// nil, so two listeners can't both navigate.
    func claim() -> Destination? {
        defer { pending = nil }
        return pending
    }

    // MARK: Parsing
    //
    // Accepts both the custom scheme (`verdure://events/<id>`) and the payload
    // form the server sends in `extra.deepLink`. Parsing is total: anything
    // unrecognised returns nil and the tap falls back to a normal launch, which
    // is strictly better than crashing or navigating somewhere arbitrary.

    nonisolated static func parse(_ raw: String?) -> Destination? {
        guard let raw, let url = URL(string: raw), url.scheme == "verdure" else { return nil }
        // verdure://events/<id>  → host "events", path "/<id>"
        let segments = ([url.host] + url.pathComponents.filter { $0 != "/" })
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard let first = segments.first else { return nil }
        switch first {
        case "events":
            guard let id = segments.dropFirst().first, !id.isEmpty else { return nil }
            return .event(id: id)
        case "perks":
            guard let id = segments.dropFirst().first, !id.isEmpty else { return nil }
            return .perk(id: id)
        case "rewards": return .rewards
        case "notifications": return .notifications
        default: return nil
        }
    }

    /// Build a destination from the two fields a push carries.
    ///
    /// Takes Strings rather than the raw `[AnyHashable: Any]` userInfo on
    /// purpose: that dictionary is not Sendable, so the caller extracts what it
    /// needs on the delegate's isolation and hands over values that can safely
    /// cross to the main actor.
    ///
    /// `deepLink` is what the server sends today; `eventId` is the fallback for
    /// notifications written before deep links existed, which are still sitting
    /// in people's inboxes and should still open something.
    nonisolated static func destination(deepLink: String?, eventId: String?) -> Destination? {
        if let d = parse(deepLink) { return d }
        if let eventId, !eventId.isEmpty { return .event(id: eventId) }
        return nil
    }
}
