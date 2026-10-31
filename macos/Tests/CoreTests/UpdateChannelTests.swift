import XCTest
@testable import MultiShiftCore

final class UpdateChannelTests: XCTestCase {
    func testFreshPilotFollowsBetaFeed() {
        XCTAssertEqual(UpdateChannel.initial(saved: nil, distribution: "beta"), .beta)
    }
    func testExplicitStablePreferenceSurvivesBetaBundle() {
        XCTAssertEqual(UpdateChannel.initial(saved: "stable", distribution: "beta"), .stable)
        XCTAssertEqual(UpdateChannel.initial(saved: "beta", distribution: "stable"), .beta)
    }
    func testUnknownPreferenceUsesValidDistributionOrStable() {
        XCTAssertEqual(UpdateChannel.initial(saved: "invalid", distribution: "beta"), .beta)
        XCTAssertEqual(UpdateChannel.initial(saved: nil, distribution: "invalid"), .stable)
    }
}
