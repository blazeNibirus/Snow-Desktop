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
    public func subtracting(_ other: SnowRect) -> [SnowRect] {
        let left = max(x, other.x), top = max(y, other.y)
        let r = min(right, other.right), b = min(bottom, other.bottom)
        guard r > left, b > top else { return [self] }
        return [SnowRect(x: x, y: y, width: width, height: top - y),
                SnowRect(x: x, y: b, width: width, height: bottom - b),
                SnowRect(x: x, y: top, width: left - x, height: b - top),
                SnowRect(x: r, y: top, width: right - r, height: b - top)]
            .filter { $0.width > 0 && $0.height > 0 }
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
    public var occluders: [SnowRect]
    public var kind: SurfaceKind
    public var roundLeft: Bool
    public var roundRight: Bool
    public init(id: UInt64, x: Double, y: Double, width: Double,
                visible: [Span]? = nil, kind: SurfaceKind = .window,
                roundLeft: Bool = true, roundRight: Bool = true, occluders: [SnowRect] = []) {
        self.id = id; self.x = x; self.y = y; self.width = width
        self.visible = visible ?? [Span(x, x + width)]; self.kind = kind
        self.roundLeft = roundLeft; self.roundRight = roundRight; self.occluders = occluders
    }
    public func supports(_ worldX: Double) -> Bool {
        visible.contains { $0.contains(worldX) }
    }
}
