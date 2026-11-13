import Foundation
import XCTest
@testable import MultiShiftCore

final class OutputOpeningTests: XCTestCase {
    func testHistoryOutputRemovedAfterConversionReportsMissingWithoutLaunching() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data([1]).write(to: url)
        try FileManager.default.removeItem(at: url)
        var launched = false
        XCTAssertEqual(OutputOpening.open(path: url.path, launch: { _ in launched = true; return false }), .missing)
        XCTAssertFalse(launched)
    }

    func testExistingOutputRejectedByMacOSReportsFailure() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(OutputOpening.open(path: url.path, launch: { _ in false }), .failed)
        XCTAssertEqual(OutputOpening.open(path: url.path, launch: { selected in
            XCTAssertEqual(selected.path, url.path)
            return true
        }), .opened)
    }
}
