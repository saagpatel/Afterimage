import XCTest
@testable import Afterimage

final class HeadingFilterTests: XCTestCase {

    // MARK: - headingDelta

    func testDeltaSameHeading() {
        let delta = HeadingFilter.headingDelta(90, 90)
        XCTAssertEqual(delta, 0, accuracy: 0.001)
    }

    func testDeltaWraparound350to10() {
        // Shortest arc between 350° and 10° is 20°
        let delta = HeadingFilter.headingDelta(350, 10)
        XCTAssertEqual(delta, 20, accuracy: 0.001)
    }

    func testDeltaWraparound10to350() {
        // Direction is irrelevant — same 20° arc
        let delta = HeadingFilter.headingDelta(10, 350)
        XCTAssertEqual(delta, 20, accuracy: 0.001)
    }

    func testDeltaOpposite() {
        let delta = HeadingFilter.headingDelta(0, 180)
        XCTAssertEqual(delta, 180, accuracy: 0.001)
    }

    // MARK: - filter

    private func makeCandidate(heading: Double?) -> MatchCandidate {
        let photo = makePhoto(heading: heading)
        return MatchCandidate(photo: photo, distanceMeters: 50)
    }

    func testFilterKeepsWithin() {
        let candidate = makeCandidate(heading: 90)
        let results = HeadingFilter.filter(
            candidates: [candidate],
            userHeading: 100,
            userHeadingAccuracy: 10,
            threshold: 45
        )
        // delta = 10 ≤ 45 → keep
        XCTAssertEqual(results.count, 1)
        if let delta = results.first?.headingDelta {
            XCTAssertEqual(delta, 10, accuracy: 0.001)
        } else {
            XCTFail("headingDelta should not be nil")
        }
    }

    func testFilterRejects() {
        let candidate = makeCandidate(heading: 200)
        let results = HeadingFilter.filter(
            candidates: [candidate],
            userHeading: 10,
            userHeadingAccuracy: 5,
            threshold: 45
        )
        // delta = 170 > 45 → reject
        XCTAssertTrue(results.isEmpty)
    }

    func testFilterSkipsBadAccuracy() {
        // accuracy > 45 → entire filter bypassed, all candidates pass unchanged
        let candidates = [
            makeCandidate(heading: 0),
            makeCandidate(heading: 180),
            makeCandidate(heading: 90),
        ]
        let results = HeadingFilter.filter(
            candidates: candidates,
            userHeading: 0,
            userHeadingAccuracy: 60,  // > 45 → skip
            threshold: 45
        )
        XCTAssertEqual(results.count, candidates.count,
            "All candidates should pass when accuracy is too coarse")
    }

    func testFilterPassesNilHeading() {
        // Photo has no heading → always passes, headingDelta stays nil
        let candidate = makeCandidate(heading: nil)
        let results = HeadingFilter.filter(
            candidates: [candidate],
            userHeading: 180,
            userHeadingAccuracy: 5,
            threshold: 45
        )
        XCTAssertEqual(results.count, 1, "Nil-heading candidate should pass through")
        XCTAssertNil(results.first?.headingDelta, "headingDelta should remain nil")
    }
}
