import CoreGraphics
import Foundation

/// One coordinate system for paths, labels and selection (local, y down).
public struct WheelGeometry: Equatable, Sendable {
    public let diameter: CGFloat
    public var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }
    public var outerRadius: CGFloat { diameter * 0.46 }
    public var cancelRadius: CGFloat { min(64, outerRadius * 0.5) }
    public var labelRadius: CGFloat { (outerRadius + cancelRadius) / 2 + 4 }

    public init(diameter: CGFloat = 400) { self.diameter = diameter }

    public func angle(for index: Int, count: Int) -> Double {
        -.pi / 2 + Double(index) * 2 * .pi / Double(max(1, count))
    }

    public func point(angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    public func sector(at point: CGPoint, count: Int) -> Int? {
        guard count > 0, point.x.isFinite, point.y.isFinite else { return nil }
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius > cancelRadius, radius <= outerRadius else { return nil }
        let step = 2 * Double.pi / Double(count)
        let angle = (atan2(dy, dx) + .pi / 2 + step / 2 + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)
        return min(count - 1, Int(floor(angle / step)))
    }

    public func frame(near cursor: CGPoint, visibleFrame: CGRect) -> CGRect {
        CGRect(x: min(max(cursor.x - diameter / 2, visibleFrame.minX), visibleFrame.maxX - diameter),
               y: min(max(cursor.y - diameter / 2, visibleFrame.minY), visibleFrame.maxY - diameter),
               width: diameter, height: diameter)
    }
}

/// Selection is armed only after intentional movement, including at clamped screen edges.
public struct WheelInteractionState: Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var selectedIndex: Int?
    public private(set) var armed = false
    private var openingCursor = CGPoint.zero

    public init() {}

    public mutating func begin(at cursor: CGPoint) {
        generation &+= 1
        openingCursor = cursor
        armed = false
        selectedIndex = nil
    }

    public mutating func update(cursor: CGPoint, localPoint: CGPoint, geometry: WheelGeometry, count: Int) {
        if !armed { armed = hypot(cursor.x - openingCursor.x, cursor.y - openingCursor.y) >= 6 }
        selectedIndex = armed ? geometry.sector(at: localPoint, count: count) : nil
    }

    public mutating func cancel() {
        generation &+= 1
        selectedIndex = nil
        armed = false
    }
}
