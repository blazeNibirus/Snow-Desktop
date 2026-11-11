import Foundation

public struct Span: Equatable, Sendable {
    public var lower: Double
    public var upper: Double
    public init(_ lower: Double, _ upper: Double) { self.lower = lower; self.upper = upper }
    public func contains(_ x: Double) -> Bool { x >= lower && x <= upper }
    public func subtracting(_ other: Span) -> [Span] {
        guard other.upper > lower, other.lower < upper else { return [self] }
        var result: [Span] = []
        if other.lower > lower { result.append(Span(lower, min(upper, other.lower))) }
        if other.upper < upper { result.append(Span(max(lower, other.upper), upper)) }
        return result
    }
}

public struct SnowRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var right: Double { x + width }
    public var bottom: Double { y + height }
    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= right && py >= y && py <= bottom
    }
    public func covers(_ other: SnowRect, tolerance: Double = 5) -> Bool {
        x <= other.x + tolerance && y <= other.y + tolerance &&
        right >= other.right - tolerance && bottom >= other.bottom - tolerance
    }
}

public enum SurfaceKind: Sendable { case window, dock }

public struct SurfaceDescriptor: Sendable {
    public var id: UInt64
    public var x: Double, y: Double, width: Double
    public var visible: [Span]
    public var kind: SurfaceKind
    public init(id: UInt64, x: Double, y: Double, width: Double,
                visible: [Span]? = nil, kind: SurfaceKind = .window) {
        self.id = id; self.x = x; self.y = y; self.width = width
        self.visible = visible ?? [Span(x, x + width)]; self.kind = kind
    }
    public func supports(_ worldX: Double) -> Bool {
        visible.contains { $0.contains(worldX) }
    }
}
