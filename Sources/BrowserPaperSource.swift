import Cocoa
import ApplicationServices

enum BrowserPaperSource {
    static let browserIDs: Set<String> = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox", "company.thebrowser.Browser"]
    static func isBrowser(_ app: NSRunningApplication) -> Bool { browserIDs.contains(app.bundleIdentifier ?? "") }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    static func usableURL(_ value: String) -> URL? {
        if let url = PaperDownload.normalizedURL(value) { return url }
        if let wrapper = URLComponents(string: value), wrapper.scheme == "chrome-extension",
           let nested = wrapper.queryItems?.first(where: { ["file", "src", "url"].contains($0.name) })?.value {
            return PaperDownload.normalizedURL(nested)
        }
        return nil
    }
    static func documentURL(_ app: NSRunningApplication) -> URL? {
        guard isBrowser(app), AXIsProcessTrusted() else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        let window = attribute(root, kAXFocusedWindowAttribute) ?? attribute(root, kAXMainWindowAttribute)
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var remaining = 280
        let started = Date()
        func visit(_ element: AXUIElement, depth: Int) -> URL? {
            guard depth < 9, remaining > 0, Date().timeIntervalSince(started) < 2 else { return nil }; remaining -= 1
            for key in [kAXURLAttribute, kAXDocumentAttribute] {
                if let value = attribute(element, key) {
                    if let url = value as? URL, let accepted = usableURL(url.absoluteString) { return accepted }
                    if let text = value as? String, let accepted = usableURL(text) { return accepted }
                }
            }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let description = ((attribute(element, kAXDescriptionAttribute) as? String ?? "") + " " + (attribute(element, kAXIdentifierAttribute) as? String ?? "")).lowercased()
            if role == kAXTextFieldRole,
               ["address", "地址", "url", "search_field"].contains(where: { description.contains($0) }),
               let text = attribute(element, kAXValueAttribute) as? String {
                if let url = usableURL(text) { return url }
                if text.contains("."), !text.contains(" "), let url = usableURL("https://" + text) { return url }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children { if let url = visit(child, depth: depth + 1) { return url } }
            }
            return nil
        }
        return visit(window as! AXUIElement, depth: 0)
    }
}
