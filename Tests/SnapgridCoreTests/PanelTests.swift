import XCTest
@testable import SnapgridCore

final class PanelTests: XCTestCase {
    // Three displays, listed out of spatial order: middle, right, left.
    let middle = Rect(x: 0, y: 0, width: 1000, height: 800)
    let right = Rect(x: 1000, y: 0, width: 1000, height: 800)
    let left = Rect(x: -1000, y: 0, width: 1000, height: 800)
    var three: [Rect] { [middle, right, left] }

    func testNeighbourWrapsInSpatialOrder() {
        XCTAssertEqual(Geometry.neighbour(of: 0, in: three, step: 1), 1)
        XCTAssertEqual(Geometry.neighbour(of: 1, in: three, step: 1), 2)
        XCTAssertEqual(Geometry.neighbour(of: 2, in: three, step: 1), 0)
        XCTAssertEqual(Geometry.neighbour(of: 0, in: three, step: -1), 2)
        XCTAssertEqual(Geometry.neighbour(of: 2, in: three, step: -1), 1)
        XCTAssertEqual(Geometry.neighbour(of: 0, in: [middle], step: 1), 0)
    }

    func testLeaderCyclesThroughDisplaysThenCloses() {
        // Opened on the middle display: right, then left, then closed.
        XCTAssertEqual(Panel.nextScreen(current: 0, first: 0, screens: three), 1)
        XCTAssertEqual(Panel.nextScreen(current: 1, first: 0, screens: three), 2)
        XCTAssertNil(Panel.nextScreen(current: 2, first: 0, screens: three))
        // A single display closes on the second press, as before.
        XCTAssertNil(Panel.nextScreen(current: 0, first: 0, screens: [middle]))
    }

    func testGridButtonsStayInRange() {
        let g = GridSize(columns: 10, rows: 1)
        XCTAssertEqual(Panel.adjust(g, columns: 1), GridSize(columns: 11, rows: 1))
        XCTAssertEqual(Panel.adjust(g, rows: -1), g)
        XCTAssertEqual(Panel.adjust(GridSize(columns: 30, rows: 5), columns: 1, rows: 1), GridSize(columns: 30, rows: 6))
    }

    func testGridMemoryResetsWhenDefaultChanges() throws {
        let suite = "snapgrid-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = Panel.GridMemory(defaults: defaults)
        let base = GridSize(columns: 10, rows: 10)

        XCTAssertEqual(memory.grid(default: base), base)
        memory.remember(GridSize(columns: 4, rows: 3), default: base)
        XCTAssertEqual(memory.grid(default: base), GridSize(columns: 4, rows: 3))
        XCTAssertEqual(memory.grid(default: GridSize(columns: 6, rows: 6)), GridSize(columns: 6, rows: 6))
    }
}

final class PlacementTests: XCTestCase {
    let a = Display(frame: Rect(x: 0, y: 0, width: 1000, height: 800),
                    visible: Rect(x: 0, y: 25, width: 1000, height: 775))
    let b = Display(frame: Rect(x: 1000, y: 0, width: 2000, height: 1000),
                    visible: Rect(x: 1000, y: 0, width: 2000, height: 1000))
    let window = Rect(x: 100, y: 100, width: 400, height: 300) // on a
    let leftHalf = Action.place(CellRange(x: 0, y: 0, w: 1, h: 1), grid: GridSize(columns: 2, rows: 1))

    func testPlacesOnTheWindowsDisplay() {
        XCTAssertEqual(Geometry.target(for: leftHalf, window: window, displays: [a, b], settings: Settings()),
                       Rect(x: 0, y: 25, width: 500, height: 775))
    }

    func testPlacesOnThePanelsDisplay() {
        XCTAssertEqual(Geometry.target(for: leftHalf, window: window, displays: [a, b], settings: Settings(), screen: 1),
                       Rect(x: 1000, y: 0, width: 1000, height: 1000))
        // An index that no longer exists (display unplugged) falls back to the window's display.
        XCTAssertEqual(Geometry.target(for: leftHalf, window: window, displays: [a, b], settings: Settings(), screen: 5),
                       Rect(x: 0, y: 25, width: 500, height: 775))
    }

    func testUsesGapAndMargin() {
        var settings = Settings()
        settings.gap = 10
        settings.margin = Insets(all: 0)
        XCTAssertEqual(Geometry.target(for: leftHalf, window: window, displays: [a], settings: settings),
                       Rect(x: 0, y: 25, width: 495, height: 775))
    }

    func testMovesBetweenDisplays() {
        XCTAssertEqual(Geometry.target(for: .nextScreen, window: window, displays: [a, b], settings: Settings()),
                       Geometry.move(window, from: a.visible, to: b.visible))
        XCTAssertEqual(Geometry.target(for: .previousScreen, window: window, displays: [a, b], settings: Settings()),
                       Geometry.move(window, from: a.visible, to: b.visible))
        XCTAssertNil(Geometry.target(for: .nextScreen, window: window, displays: [a], settings: Settings()))
        XCTAssertNil(Geometry.target(for: leftHalf, window: window, displays: [], settings: Settings()))
    }
}
