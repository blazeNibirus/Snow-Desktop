import Foundation

public enum DockLayout {
    /// The full-width mode uses the system work-area inset even if AX is unavailable.
    public static func surfaces(frame: SnowRect, workArea: SnowRect, icons: [SnowRect],
                                fullWidth: Bool, bottomDock: Bool = true,
                                autoHidden: Bool = false) -> [SurfaceDescriptor] {
        guard bottomDock else { return [] }
        let icons = icons.filter { $0.x < frame.right && $0.right > frame.x &&
            $0.y < frame.bottom - 2 && $0.bottom > frame.y }
        let reserved = frame.bottom - workArea.bottom
        let hasShelf = !autoHidden && reserved > 20
        if fullWidth {
            guard hasShelf || !icons.isEmpty else { return [] }
            let y = hasShelf ? workArea.bottom : (icons.map(\.y).max()! - 5)
            return [SurfaceDescriptor(id: UInt64.max - 1, x: 0, y: y - frame.y,
                width: frame.width, kind: .dock, roundLeft: false, roundRight: false)]
        }
        guard !icons.isEmpty else { return [] }
        let left = max(frame.x, icons.map(\.x).min()! - 9)
        let right = min(frame.right, icons.map(\.right).max()! + 9)
        let top = icons.map(\.y).min()!, bottom = icons.map(\.bottom).max()!
        guard right - left > (bottom - top) * 1.8,
              bottom > frame.bottom - 180 else { return [] }
        let base = hasShelf ? workArea.bottom : icons.map(\.y).max()! - 5
        let sorted = icons.sorted { $0.x < $1.x }
        return sorted.enumerated().map { index, icon in
            let start = index == 0 ? left : (sorted[index - 1].right + icon.x) / 2
            let end = index == sorted.count - 1 ? right : (icon.right + sorted[index + 1].x) / 2
            return SurfaceDescriptor(id: UInt64.max - UInt64(index + 100),
                x: start - frame.x, y: min(base, icon.y - 5) - frame.y,
                width: max(2, end - start), kind: .dock,
                roundLeft: index == 0, roundRight: index == sorted.count - 1)
        }
    }
}
