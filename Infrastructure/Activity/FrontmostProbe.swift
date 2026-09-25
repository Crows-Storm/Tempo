import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum FrontmostProbe {
    struct Snapshot: Sendable {
        var appName: String
        var bundleID: String
        var windowTitle: String
    }

    private static var cachePID: pid_t = 0
    private static var cacheTitle = ""
    private static var cacheDate = Date.distantPast

    static var isTrusted: Bool {
        trustedWithoutPrompt()
    }

    @discardableResult
    static func promptTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func capture() -> Snapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        if SystemChrome.isIgnored(appName: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "") {
            return nil
        }
        let name = app.localizedName ?? "App"
        let title = readTitle(pid: app.processIdentifier)
        return Snapshot(appName: name, bundleID: app.bundleIdentifier ?? "", windowTitle: title)
    }

    static var isScreenCaptureTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func promptScreenCapture() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenCaptureSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    private static func trustedWithoutPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func readTitle(pid: pid_t) -> String {
        if WindowTitle.shouldReuseCache(
            pid: pid,
            cachedPID: cachePID,
            cachedTitle: cacheTitle,
            cachedAt: cacheDate
        ) {
            return cacheTitle
        }
        var title = ""
        if trustedWithoutPrompt() {
            title = axTitle(pid: pid)
        }
        if title.isEmpty {
            title = cgTitle(pid: pid)
        }
        cachePID = pid
        cacheTitle = title
        cacheDate = title.isEmpty ? .distantPast : .now
        return title
    }

    private static func axTitle(pid: pid_t) -> String {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        if let window = copyElement(application, kAXFocusedWindowAttribute as String) {
            if let title = nonempty(copyString(window, kAXTitleAttribute as String)) { return title }
            if let title = nonempty(copyString(window, kAXDescriptionAttribute as String)) { return title }
            if let document = nonempty(WindowTitle.documentName(copyString(window, kAXDocumentAttribute as String))) {
                return document
            }
        }
        for window in copyElements(application, kAXWindowsAttribute as String) {
            if let title = nonempty(copyString(window, kAXTitleAttribute as String)) { return title }
            if let title = nonempty(copyString(window, kAXDescriptionAttribute as String)) { return title }
        }
        if let focused = copyElement(application, kAXFocusedUIElementAttribute as String) {
            var node: AXUIElement? = focused
            for _ in 0..<8 {
                guard let current = node else { break }
                if let window = copyElement(current, kAXWindowAttribute as String),
                   let title = nonempty(copyString(window, kAXTitleAttribute as String)) {
                    return title
                }
                node = copyElement(current, kAXParentAttribute as String)
            }
        }
        return ""
    }

    private static func cgTitle(pid: pid_t) -> String {
        let onScreen = titleFromList([.optionOnScreenOnly, .excludeDesktopElements], pid: pid)
        if !onScreen.isEmpty { return onScreen }
        return titleFromList([.excludeDesktopElements], pid: pid)
    }

    private static func titleFromList(_ options: CGWindowListOption, pid: pid_t) -> String {
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return ""
        }
        return WindowTitle.fromWindowList(info, pid: Int(pid))
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func copyElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let objects = value as? [AnyObject] else {
            return []
        }
        return objects.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return ""
        }
        return WindowTitle.string(from: value)
    }

    private static func nonempty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
