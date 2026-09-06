import XCTest
import CoreLocation
@testable import Verdure

// MARK: - GameStateManager transaction-logic smoke tests
//
// These cover the CLIENT half of the earn/redeem pipeline: optimistic awards,
// double-earn guards, the pending-op queue (incl. proof-photo spooling and
// persistence across relaunches), and the signed-out redeem path. The SERVER
// half (Cloud Functions transactions) is validated by its own idempotent
// design + typescript build; no network is touched here — with no
// FunctionsService connected, flushPendingOps() is a guarded no-op.

@MainActor
final class GameStateManagerTests: XCTestCase {

    private let gameStateKeys = [
        "collectedPlaceIDs", "checkedInEventIDs", "pointsBalance", "lifetimePoints",
        "redeemedRewardIDs", "savedEventIDs", "savedPlaceIDs", "pendingServerOps",
        "earnHistory", "streakCount", "streakLastDay", "challengeBonusXP",
        "completedChallengeKeys", "earnedBadges", "notificationInbox",
    ]

    override func setUp() async throws {
        wipePersistedState()
    }

    override func tearDown() async throws {
        wipePersistedState()
        try? FileManager.default.removeItem(at: GameStateManager.proofsDirectory)
    }

    private func wipePersistedState() {
        for key in gameStateKeys { UserDefaults.standard.removeObject(forKey: key) }
        // Suppress the demo seed so managers start empty and deterministic.
        UserDefaults.standard.set(true, forKey: "gameStateSeeded_v2")
    }

    private func freshManager() -> GameStateManager { GameStateManager() }

    // Fixtures use their OWN ids: SampleData ids are refused at the earn boundary
    // (fabricated content can never earn), so a test that used them would prove
    // nothing.
    private var sampleEvent: Event { TestFixtures.event }            // 200-pt hackathon
    private var samplePlace: CollectiblePlace { TestFixtures.collectible }
    private var sampleReward: Reward { SampleData.rewards[0] }       // cheapest catalog entry

    // MARK: Check-in

    func testCheckInAwardsPointsOnceAndQueuesServerOp() throws {
        let state = freshManager()
        let coordinate = CLLocationCoordinate2D(latitude: 44.98, longitude: -93.26)

        let awarded = state.checkInEvent(sampleEvent, proofPhoto: nil, userCoordinate: coordinate)

        XCTAssertEqual(awarded, sampleEvent.pointValue)
        XCTAssertEqual(state.pointsBalance, sampleEvent.pointValue)
        XCTAssertEqual(state.lifetimePoints, sampleEvent.pointValue)
        XCTAssertTrue(state.isCheckedIn(sampleEvent.id))
        XCTAssertEqual(state.pendingOps.count, 1)
        let op = try XCTUnwrap(state.pendingOps.first)
        XCTAssertEqual(op.kind, .checkIn)
        XCTAssertEqual(op.id, sampleEvent.id)
        XCTAssertEqual(op.points, sampleEvent.pointValue)
        XCTAssertEqual(op.lat, coordinate.latitude)
        XCTAssertEqual(op.lon, coordinate.longitude)
    }

    func testDoubleCheckInIsANoOp() {
        let state = freshManager()
        _ = state.checkInEvent(sampleEvent)

        let second = state.checkInEvent(sampleEvent)

        XCTAssertEqual(second, 0, "double check-in must award nothing")
        XCTAssertEqual(state.pointsBalance, sampleEvent.pointValue, "balance unchanged by replay")
        XCTAssertEqual(state.pendingOps.count, 1, "no duplicate server op queued")
    }

    func testCheckInSpoolsProofPhotoToDisk() throws {
        let state = freshManager()
        let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        _ = state.checkInEvent(sampleEvent, proofPhoto: fakeJPEG,
                               userCoordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2))

        let op = try XCTUnwrap(state.pendingOps.first)
        let file = try XCTUnwrap(op.proofFile, "check-in with a photo must spool a proof file")
        let url = GameStateManager.proofsDirectory.appendingPathComponent(file)
        XCTAssertEqual(try Data(contentsOf: url), fakeJPEG, "spooled bytes must match the photo")
        XCTAssertNil(op.proofPath, "storage path is only set after a real upload")
    }

    // MARK: Place collection

    func testCollectPlaceAwardsOnceAndQueuesOp() {
        let state = freshManager()

        let first = state.collectPlace(samplePlace)
        let second = state.collectPlace(samplePlace)

        XCTAssertEqual(first, samplePlace.pointValue)
        XCTAssertEqual(second, 0, "double collect must award nothing")
        XCTAssertEqual(state.pointsBalance, samplePlace.pointValue)
        XCTAssertTrue(state.isCollected(samplePlace.id))
        XCTAssertEqual(state.pendingOps.filter { $0.kind == .collect }.count, 1)
    }

    // MARK: Redeem (signed-out local path — server path needs live Functions)

    func testRedeemSignedOutIsRefusedNotFaked() async {
        // The old "demo mode" deducted points locally and delivered nothing —
        // a fabricated reward. Signed out, redemption must be refused outright.
        let state = freshManager()
        state.pointsBalance = sampleReward.pointCost + 250

        let result = await state.redeemReward(sampleReward)

        XCTAssertEqual(result, .signInRequired)
        XCTAssertEqual(state.pointsBalance, sampleReward.pointCost + 250, "no points may move without a server")
        XCTAssertFalse(state.isRedeemed(sampleReward.id))
    }

    func testSampleContentCanNeverEarn() {
        let state = freshManager()
        XCTAssertEqual(state.checkInEvent(SampleData.events[0]), 0)
        XCTAssertEqual(state.collectPlace(SampleData.collectiblePlaces[0]), 0)
        XCTAssertEqual(state.pointsBalance, 0)
        XCTAssertTrue(state.pendingOps.isEmpty, "fixture ids must never reach the server queue")
    }

    func testRedeemRejectsInsufficientPoints() async {
        let state = freshManager()
        state.pointsBalance = sampleReward.pointCost - 1

        let result = await state.redeemReward(sampleReward)

        XCTAssertEqual(result, .notEnoughPoints)
        XCTAssertEqual(state.pointsBalance, sampleReward.pointCost - 1, "no deduction on failure")
        XCTAssertFalse(state.isRedeemed(sampleReward.id))
    }

    func testFastDoubleRedeemOnlyDeductsOnce() async {
        let state = freshManager()
        let reward = sampleReward                      // hoisted: async-let children may not touch self
        state.pointsBalance = reward.pointCost         // can afford exactly one

        // Fire two redemptions back-to-back (the "fast double-tap").
        async let a = state.redeemReward(reward)
        async let b = state.redeemReward(reward)
        let results = await [a, b]

        XCTAssertEqual(results.filter { $0 == .success }.count, 1, "exactly one succeeds")
        XCTAssertEqual(state.pointsBalance, 0, "points deducted exactly once")
        XCTAssertTrue(state.isRedeemed(reward.id))
    }

    // MARK: Queue persistence (offline replay survives relaunch)

    func testPendingOpsPersistAcrossManagerInstances() {
        let first = freshManager()
        _ = first.checkInEvent(sampleEvent, userCoordinate: CLLocationCoordinate2D(latitude: 3, longitude: 4))
        _ = first.collectPlace(samplePlace)
        XCTAssertEqual(first.pendingOps.count, 2)

        // Simulate an app relaunch: a brand-new manager must reload the queue.
        let second = GameStateManager()
        XCTAssertEqual(second.pendingOps, first.pendingOps,
                       "queued server ops must survive relaunch for offline replay")
    }

    func testLegacyQueuePayloadStillDecodes() throws {
        // v1 ops (before proof/GPS fields existed) must keep decoding.
        let legacyJSON = #"[{"kind":"checkIn","id":"old-event","category":"Social","points":100}]"#
        UserDefaults.standard.set(Data(legacyJSON.utf8), forKey: "pendingServerOps")

        let state = GameStateManager()

        XCTAssertEqual(state.pendingOps.count, 1)
        let op = try XCTUnwrap(state.pendingOps.first)
        XCTAssertEqual(op.id, "old-event")
        XCTAssertNil(op.lat)
        XCTAssertNil(op.proofFile)
    }

    // MARK: Reset

    func testResetAllClearsEverything() {
        let state = freshManager()
        _ = state.checkInEvent(sampleEvent, proofPhoto: Data([0xFF, 0xD8]),
                               userCoordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        _ = state.collectPlace(samplePlace)

        state.resetAll()

        XCTAssertEqual(state.pointsBalance, 0)
        XCTAssertEqual(state.lifetimePoints, 0)
        XCTAssertTrue(state.checkedInEventIDs.isEmpty)
        XCTAssertTrue(state.collectedPlaceIDs.isEmpty)
        XCTAssertTrue(state.redeemedRewardIDs.isEmpty)
        XCTAssertTrue(state.pendingOps.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: GameStateManager.proofsDirectory
                .appendingPathComponent(StorageService.proofFileName(for: sampleEvent.id)).path),
            "spooled proof photos are wiped on reset")
    }
}
