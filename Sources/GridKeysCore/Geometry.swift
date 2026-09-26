import Foundation

/// A rectangle in top-left-origin coordinates (the Accessibility API's coordinate space).
public struct Rect: Equatable, CustomStringConvertible {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var description: String { "(\(x), \(y), \(width)x\(height))" }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < maxX && py >= y && py < maxY
    }

    public func intersectionArea(_ o: Rect) -> Double {
        let w = min(maxX, o.maxX) - max(x, o.x)
        let h = min(maxY, o.maxY) - max(y, o.y)
        return w > 0 && h > 0 ? w * h : 0
    }
}

public enum Geometry {
    /// Frame for a cell selection on a screen's visible area. `gap` is the spacing between
    /// adjacent windows and between windows and the screen edge.
    public static func frame(for cells: CellRange, grid: GridSize, in visible: Rect, gap: Double = 0) -> Rect {
        let half = gap / 2
        let usable = Rect(x: visible.x + half, y: visible.y + half,
                          width: visible.width - gap, height: visible.height - gap)
        let cellW = usable.width / Double(grid.columns)
        let cellH = usable.height / Double(grid.rows)
        let raw = Rect(x: usable.x + Double(cells.x) * cellW,
                       y: usable.y + Double(cells.y) * cellH,
                       width: Double(cells.w) * cellW,
                       height: Double(cells.h) * cellH)
        return Rect(x: (raw.x + half).rounded(), y: (raw.y + half).rounded(),
                    width: (raw.width - gap).rounded(), height: (raw.height - gap).rounded())
    }

    /// Index of the screen a window belongs to: the one containing its centre, else the one it overlaps most.
    public static func screenIndex(for window: Rect, screens: [Rect]) -> Int? {
        if let i = screens.firstIndex(where: { $0.contains(x: window.midX, y: window.midY) }) { return i }
        let best = screens.enumerated().max { $0.element.intersectionArea(window) < $1.element.intersectionArea(window) }
        guard let best, best.element.intersectionArea(window) > 0 else { return screens.isEmpty ? nil : 0 }
        return best.offset
    }

    /// Maps a window frame from one screen to another, keeping its relative position and size.
    public static func move(_ window: Rect, from source: Rect, to target: Rect) -> Rect {
        let rx = (window.x - source.x) / source.width
        let ry = (window.y - source.y) / source.height
        let rw = window.width / source.width
        let rh = window.height / source.height
        var w = min(rw * target.width, target.width)
        var h = min(rh * target.height, target.height)
        var x = target.x + rx * target.width
        var y = target.y + ry * target.height
        x = min(max(x, target.x), target.maxX - w)
        y = min(max(y, target.y), target.maxY - h)
        w.round(); h.round()
        return Rect(x: x.rounded(), y: y.rounded(), width: w, height: h)
    }

    /// Screens ordered left-to-right (then top-to-bottom) for next/previous-screen cycling.
    public static func spatialOrder(_ screens: [Rect]) -> [Int] {
        screens.indices.sorted {
            let a = screens[$0], b = screens[$1]
            return a.x != b.x ? a.x < b.x : a.y < b.y
        }
    }
}
