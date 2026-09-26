#if os(macOS)
import AppKit
import ApplicationServices
import SnapgridCore

enum WindowMoverError: Error, CustomStringConvertible {
    case notTrusted, noWindow, cannotReadFrame, noScreen

    var description: String {
        switch self {
        case .notTrusted: return "Accessibility permission not granted"
        case .noWindow: return "no focused window"
        case .cannotReadFrame: return "cannot read the window's frame"
        case .noScreen: return "no screen found"
        }
    }
}

/// Moves the focused window using the Accessibility API. All rects are in AX
/// coordinates: origin at the top-left of the primary display, y growing downwards.
enum WindowMover {
    static func screens() -> [Display] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        func convert(_ r: NSRect) -> Rect {
            Rect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
        return NSScreen.screens.map { Display(frame: convert($0.frame), visible: convert($0.visibleFrame)) }
    }

    /// `screen` (an index into `NSScreen.screens`) overrides the display a placement goes to.
    static func perform(_ action: Action, settings: SnapgridCore.Settings, screen: Int? = nil) throws {
        guard AXIsProcessTrusted() else { throw WindowMoverError.notTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw WindowMoverError.noWindow }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = copyElement(axApp, kAXFocusedWindowAttribute) else { throw WindowMoverError.noWindow }
        guard let current = frame(of: window) else { throw WindowMoverError.cannotReadFrame }

        let displays = screens()
        guard !displays.isEmpty else { throw WindowMoverError.noScreen }
        if let target = Geometry.target(for: action, window: current, displays: displays, settings: settings, screen: screen) {
            setFrame(window, target, app: axApp)
        }
    }

    /// Index into `NSScreen.screens` of the display showing the focused window, or the one under the mouse.
    static func focusedScreen() -> Int? {
        if AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
           let window = copyElement(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
           let current = frame(of: window),
           let index = Geometry.screenIndex(for: current, screens: screens().map(\.frame)),
           index < NSScreen.screens.count {
            return index
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? (NSScreen.screens.isEmpty ? nil : 0)
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(of window: AXUIElement) -> Rect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return Rect(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    private static func setFrame(_ window: AXUIElement, _ rect: Rect, app: AXUIElement) {
        // Apps with "enhanced user interface" on (set by assistive tools) animate AX
        // resizes and end up at the wrong size; switch it off for the duration of the move.
        let enhancedKey = "AXEnhancedUserInterface" as CFString
        var enhancedRef: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(app, enhancedKey, &enhancedRef) == .success
            && (enhancedRef as? Bool) == true
        if wasEnhanced { AXUIElementSetAttributeValue(app, enhancedKey, kCFBooleanFalse) }
        defer { if wasEnhanced { AXUIElementSetAttributeValue(app, enhancedKey, kCFBooleanTrue) } }

        var size = CGSize(width: rect.width, height: rect.height)
        var point = CGPoint(x: rect.x, y: rect.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let pointValue = AXValueCreate(.cgPoint, &point) else { return }
        // Size, then position, then size again: apps clamp sizes to the current screen,
        // so a window moving to a different display needs the second resize.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
}
#endif
