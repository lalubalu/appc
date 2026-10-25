import Foundation

/// The two first-launch loads, started together.
///
/// CAC 2026 (1.4). `VerdureApp.connectServicesIfNeeded` awaited the places
/// fetch and THEN the events fetch, so the Events tab sat empty for as long as
/// Overpass took to answer or time out — about 22 seconds on a bad day — for
/// data it never shows. The two loads share nothing, so they start at the same
/// instant and the slower one no longer delays the other.
///
/// Kept as a tiny, dependency-free function so a unit test can prove the
/// concurrency with injected closures (see `StartupFetchesTests`).
enum StartupFetches {
    static func run(places: @escaping @Sendable () async -> Void,
                    events: @escaping @Sendable () async -> Void) async {
        async let placesDone: Void = places()
        async let eventsDone: Void = events()
        _ = await (placesDone, eventsDone)
    }
}
