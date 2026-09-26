import Foundation

extension Geometry {
    /// The display `step` places after `index` in left-to-right order, wrapping around.
    public static func neighbour(of index: Int, in screens: [Rect], step: Int) -> Int {
        let order = spatialOrder(screens)
        guard let pos = order.firstIndex(of: index) else { return index }
        let n = order.count
        return order[((pos + step) % n + n) % n]
    }
}

/// Rules for Divvy's panel (the grid shown by the leader key).
public enum Panel {
    public static let sizes = 1...30

    /// Pressing the leader again moves the panel to the next display; nil (close it)
    /// once it would come back to the display it opened on.
    public static func nextScreen(current: Int, first: Int, screens: [Rect]) -> Int? {
        let next = Geometry.neighbour(of: current, in: screens, step: 1)
        return next == first ? nil : next
    }

    /// The panel's grid after pressing + or −, kept within `sizes`.
    public static func adjust(_ grid: GridSize, columns: Int = 0, rows: Int = 0) -> GridSize {
        func clamp(_ v: Int) -> Int { min(max(v, sizes.lowerBound), sizes.upperBound) }
        return GridSize(columns: clamp(grid.columns + columns), rows: clamp(grid.rows + rows))
    }

    /// Remembers the size picked in the panel until the default grid in Settings changes.
    public struct GridMemory {
        let defaults: UserDefaults
        static let gridKey = "popupGrid", baseKey = "popupGridBase"

        public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

        public func grid(default base: GridSize) -> GridSize {
            guard defaults.string(forKey: Self.baseKey) == base.description,
                  let saved = defaults.string(forKey: Self.gridKey).flatMap(GridSize.parse) else { return base }
            return saved
        }

        public func remember(_ grid: GridSize, default base: GridSize) {
            defaults.set(grid.description, forKey: Self.gridKey)
            defaults.set(base.description, forKey: Self.baseKey)
        }
    }
}
