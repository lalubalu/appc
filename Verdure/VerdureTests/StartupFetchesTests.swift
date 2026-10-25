import XCTest
@testable import Verdure

/// CAC 2026 (1.4): the events load must not wait behind the places load.
///
/// No sleeps and no timing thresholds: the places closure parks on a
/// continuation that ONLY the events closure resumes. If the two ran one after
/// the other (the old `await places; await events`), the events closure would
/// never start, the places closure would never finish, and the expectation
/// would time out — which is the failure. Running in parallel, it completes
/// immediately.
final class StartupFetchesTests: XCTestCase {
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in continuation = c }
        }
        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    func testEventsStartWhilePlacesAreStillLoading() {
        let gate = Gate()
        let order = OrderLog()
        let done = expectation(description: "both loads finished")
        Task {
            await StartupFetches.run(
                places: {
                    await order.record("places:start")
                    await gate.wait()                 // resumed only by the events closure
                    await order.record("places:end")
                },
                events: {
                    await order.record("events:start")
                    await gate.open()
                    await order.record("events:end")
                })
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        let events = order.snapshot
        XCTAssertTrue(events.contains("events:start") && events.contains("places:end"), "\(events)")
        XCTAssertLessThan(events.firstIndex(of: "events:start")!, events.firstIndex(of: "places:end")!,
                          "events must start before places finish: \(events)")
    }

    func testBothClosuresRunExactlyOnce() {
        let order = OrderLog()
        let done = expectation(description: "finished")
        Task {
            await StartupFetches.run(places: { await order.record("places") }, events: { await order.record("events") })
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(order.snapshot.sorted(), ["events", "places"])
    }

    /// Thread-safe append-only log.
    private final class OrderLog: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func record(_ s: String) async { lock.lock(); entries.append(s); lock.unlock() }
        var snapshot: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    }
}
