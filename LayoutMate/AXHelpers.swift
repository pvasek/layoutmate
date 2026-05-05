import ApplicationServices
import CoreGraphics
import AppKit

/// Thin Swift wrappers around the C Accessibility API.
/// These keep the rest of the app free of `CFTypeRef` plumbing.
enum AX {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let s = ref as? String
        else { return nil }
        return s
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let b = ref as? Bool
        else { return nil }
        return b
    }

    static func windows(of appElement: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref) == .success,
              let array = ref as? [AXUIElement]
        else { return [] }
        return array
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let raw = ref,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let value = raw as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let raw = ref,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let value = raw as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let p = point(window, kAXPositionAttribute),
              let s = size(window, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    static func setFrame(_ frame: CGRect, on window: AXUIElement) -> Bool {
        var pos = frame.origin
        var sz = frame.size
        guard let posValue = AXValueCreate(.cgPoint, &pos),
              let sizeValue = AXValueCreate(.cgSize, &sz)
        else { return false }
        // Position → size → position again. Some apps clamp size against the current
        // screen's bounds, which can shove a window out of place if we set position last.
        // Setting position twice (book-ending the size change) makes the final placement stick.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        return true
    }
}
