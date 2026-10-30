import CoreGraphics
import XCTest
@testable import MultiShiftCore

final class WheelGeometryTests: XCTestCase {
    let geometry = WheelGeometry()

    func testEveryVisibleSectorCenterAndBothSidesOfItsBoundary() {
        for count in 1...10 {
            let step = 2 * Double.pi / Double(count)
            for index in 0..<count {
                let angle = geometry.angle(for: index, count: count)
                for delta in [-0.49, 0, 0.49] {
                    XCTAssertEqual(geometry.sector(at: geometry.point(angle: angle + delta * step, radius: 128), count: count), index)
                }
                let next = (index + 1) % count
                XCTAssertEqual(geometry.sector(at: geometry.point(angle: angle + 0.51 * step, radius: 128), count: count), next)
            }
        }
    }

    func testEntireVisibleCenterAndOutsideCancel() {
        for radius: CGFloat in [0, 54, 61, 62, 63.9, 64, 184.1, 200] {
            XCTAssertNil(geometry.sector(at: geometry.point(angle: 0, radius: radius), count: 10))
        }
        XCTAssertNotNil(geometry.sector(at: geometry.point(angle: 0, radius: 64.1), count: 10))
        XCTAssertNil(geometry.sector(at: CGPoint(x: CGFloat.infinity, y: 0), count: 10))
        XCTAssertNil(geometry.sector(at: geometry.center, count: 0))
    }

    func testClampedOpeningCannotRunAnActionUntilSixPointsOfMovement() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1440, y: -100, width: 1440, height: 900)]
        for screen in screens {
            for cursor in [CGPoint(x: screen.minX + 10, y: screen.midY), CGPoint(x: screen.maxX - 10, y: screen.midY)] {
                let frame = geometry.frame(near: cursor, visibleFrame: screen)
                XCTAssertTrue(screen.contains(frame))
                var state = WheelInteractionState()
                state.begin(at: cursor)
                let local = CGPoint(x: cursor.x - frame.minX, y: frame.maxY - cursor.y)
                state.update(cursor: cursor, localPoint: local, geometry: geometry, count: 10)
                XCTAssertNil(state.selectedIndex)
                XCTAssertFalse(state.armed)
                state.update(cursor: CGPoint(x: cursor.x + 5.9, y: cursor.y), localPoint: local, geometry: geometry, count: 10)
                XCTAssertFalse(state.armed)
                state.update(cursor: CGPoint(x: cursor.x + 6, y: cursor.y), localPoint: geometry.point(angle: 0, radius: 128), geometry: geometry, count: 10)
                XCTAssertNotNil(state.selectedIndex)
                let generation = state.generation
                state.cancel()
                XCTAssertNil(state.selectedIndex)
                state.begin(at: cursor)
                XCTAssertGreaterThan(state.generation, generation)
                XCTAssertFalse(state.armed)
            }
        }
    }
}
