import Foundation

public enum SnowBankProfile {
    /// A smooth cap has zero height and a horizontal tangent at the physical edge.
    public static func edgeFactor(x: Double, width: Double, radius: Double = 18,
                                  roundLeft: Bool = true, roundRight: Bool = true) -> Double {
        guard width > 0, x >= 0, x <= width else { return 0 }
        let cap = max(0.1, min(radius, width / 2))
        func smooth(_ distance: Double) -> Double {
            let t = max(0, min(1, distance / cap))
            return t * t * (3 - 2 * t)
        }
        return min(roundLeft ? smooth(x) : 1, roundRight ? smooth(width - x) : 1)
    }
}
