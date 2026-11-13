import Cocoa
import Carbon
import ApplicationServices

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
    let v = NSTextField(wrappingLabelWithString: text)
    v.font = .systemFont(ofSize: size, weight: weight)
    return v
}
func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v }
func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
    let v = NSButton(title: title, target: target, action: action); v.bezelStyle = .rounded; return v
}

@MainActor
class AssistantApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    var window: NSWindow!
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem!
    var original = NSTextView()
    var result = NSTextView()
    var modePicker: NSSegmentedControl!
    var runButton: NSButton!
    var copyButton: NSButton!
    var cancelButton: NSButton!
    var selectionPermissionButton: NSButton?
    var statusLabel = label("选中文字后按 ⌃⌥⌘P，或将文字粘贴到左侧。")
    var inputLabel = label("原文", size: 14, weight: .semibold)
    var progress = NSProgressIndicator()
    var keyField: NSSecureTextField!
    var modelPicker: NSPopUpButton!
    var settingsStatus: NSTextField!
    var saveButton: NSButton!
    var activeTask: Task<Void, Never>?
    var validationTask: Task<Void, Never>?
    var requestID = UUID()
    var hotKey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var readingHotKeys: [EventHotKeyRef] = []
    var reader: PaperReaderController?
    var lastBrowser: NSRunningApplication?
    var browserObserver: NSObjectProtocol?
    var captureForReading = false
    var capturedDocumentURL: String?
    var externalApp: NSRunningApplication?
    var capturedText = ""
    var captureID = UUID()
    var mode: ActionMode { ActionMode(rawValue: modePicker.selectedSegment) ?? .polish }
    var model: String { UserDefaults.standard.string(forKey: "deepseekModel") ?? "deepseek-flash" }
    var busy: Bool { activeTask != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        buildMenu()
        buildWindow()
        registerShortcut()
        if let front = NSWorkspace.shared.frontmostApplication, BrowserPaperSource.isBrowser(front) { lastBrowser = front }
        browserObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, BrowserPaperSource.isBrowser(app) {
                DispatchQueue.main.async { self?.lastBrowser = app }
            }
        }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        showWindow()
        if CommandLine.arguments.contains("--demo") { showDemo() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { refreshSelectionPermission() }

    func refreshSelectionPermission() {
        let granted = AXIsProcessTrusted()
        selectionPermissionButton?.title = granted ? "选文权限已开启" : "启用选文快捷键"
        selectionPermissionButton?.isEnabled = !granted
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "DeepSeek 设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出学术助手", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "学术助手")
        let menu = NSMenu()
        for (title, action) in [("打开学术助手", #selector(showWindow)), ("论文阅读", #selector(showReader)), ("读取浏览器论文  ⌃⌥⌘R", #selector(readBrowserPaper)), ("选中段落提问  ⌃⌥⌘D", #selector(captureReadingSelection)), ("润色选中文字  ⌃⌥⌘P", #selector(captureSelection)), ("从剪贴板读取", #selector(pasteSource)), ("DeepSeek 设置…", #selector(showSettings)), ("启用选文快捷键…", #selector(requestAccessibility)), ("查看使用说明", #selector(showHelp))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator()); menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    func textPanel(_ textView: NSTextView, title: NSTextField, id: String, editable: Bool) -> NSStackView {
        textView.isRichText = false; textView.isEditable = editable; textView.isSelectable = true
        textView.font = .systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.setAccessibilityLabel(title.stringValue)
        textView.setAccessibilityIdentifier(id)
        let scroll = NSScrollView()
        scroll.documentView = textView; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let panel = NSStackView(views: [title, scroll]); panel.orientation = .vertical; panel.alignment = .leading; panel.spacing = 8
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo: panel.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)])
        return panel
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1030, height: 690), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "学术助手 · DeepSeek"
        window.minSize = NSSize(width: 820, height: 570)
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        let heading = label("在这里，看清每一次修改。", size: 25, weight: .semibold)
        let settings = button("DeepSeek 设置", self, #selector(showSettings))
        let header = NSStackView(views: [heading, spacer(), button("论文阅读", self, #selector(showReader)), settings]); header.orientation = .horizontal; header.spacing = 10
        let hint = label("Overleaf / 浏览器 PDF  ·  选中文字 → ⌃⌥⌘P → 预览 → 复制结果", size: 13)
        hint.textColor = .secondaryLabelColor
        modePicker = NSSegmentedControl(labels: ["英文润色", "中文解释", "中英翻译"], trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        modePicker.selectedSegment = 0
        modePicker.toolTip = "英文润色：按你的学术写作规范修改；中文解释：帮助理解段落；中英翻译：英文译中文，中文译学术英文。"
        let paste = button("粘贴文字", self, #selector(pasteSource))
        let authorize = button("启用选文快捷键", self, #selector(requestAccessibility))
        selectionPermissionButton = authorize
        refreshSelectionPermission()
        let tools = NSStackView(views: [modePicker, spacer(), paste, authorize]); tools.orientation = .horizontal; tools.spacing = 10
        let panels = NSStackView(views: [textPanel(original, title: inputLabel, id: "sourceText", editable: true), textPanel(result, title: label("结果预览", size: 14, weight: .semibold), id: "resultText", editable: false)])
        panels.orientation = .horizontal; panels.distribution = .fillEqually; panels.spacing = 18
        original.delegate = self
        runButton = button("开始润色", self, #selector(run)); runButton.keyEquivalent = "\r"; runButton.keyEquivalentModifierMask = [.command]
        runButton.bezelColor = .systemTeal
        copyButton = button("复制结果", self, #selector(copyResult)); copyButton.isEnabled = false
        cancelButton = button("取消", self, #selector(cancel)); cancelButton.isHidden = true
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let actions = NSStackView(views: [runButton, cancelButton, progress, spacer(), copyButton]); actions.orientation = .horizontal; actions.spacing = 10
        statusLabel.textColor = .secondaryLabelColor
        let privacy = label("仅在你发起处理时，将左侧文字发送至 DeepSeek。结果不会自动替换原文。", size: 11)
        privacy.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [header, hint, tools, panels, actions, statusLabel, privacy])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 15
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)])
        for view in [header, tools, panels, actions, statusLabel] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        panels.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @objc func showWindow() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func quit() { activeTask?.cancel(); validationTask?.cancel(); reader?.cancel(); reader?.flushNotes(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { reader?.flushNotes() }
    @objc func showReader() {
        do { if reader == nil { reader = try PaperReaderController(owner: self) }; reader?.show() }
        catch { showWindow(); status("阅读资料夹无法打开：\(error.localizedDescription)", error: true) }
    }
    @objc func readBrowserPaper() {
        let front = NSWorkspace.shared.frontmostApplication
        let browser = front.flatMap { BrowserPaperSource.isBrowser($0) ? $0 : nil } ?? lastBrowser
        let url = browser.flatMap { BrowserPaperSource.documentURL($0) }
        showReader()
        if let url { reader?.openURL(url) }
        else {
            reader?.status("未取到浏览器 PDF 地址。可点击“粘贴论文链接”或“导入 PDF”；也可先切到浏览器再按 ⌃⌥⌘R。", error: true)
        }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        showReader()
        if let file = filenames.first { reader?.openURL(URL(fileURLWithPath: file)) }
        sender.reply(toOpenOrPrint: .success)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { if let reader { reader.show() } else { showWindow() } }
        return true
    }
    @objc func showHelp() {
        if let url = Bundle.main.url(forResource: "使用说明", withExtension: "txt") {
            NSWorkspace.shared.open(url)
        }
    }
    func status(_ message: String, error: Bool = false) { statusLabel.stringValue = message; statusLabel.textColor = error ? .systemRed : .secondaryLabelColor }
    @objc func modeChanged() { runButton.title = mode.verb; result.string = ""; copyButton.isEnabled = false; status("点击“\(mode.verb)”处理左侧文字。") }
    func textDidChange(_ notification: Notification) { copyButton.isEnabled = false; if !result.string.isEmpty { status("原文已改变，请重新处理以更新结果。") } }

    @objc func pasteSource() {
        guard !busy else { status("请等待当前请求结束，或先取消。", error: true); return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showWindow(); status("剪贴板中没有文字。先在浏览器中选中文字并按 ⌘C。", error: true); return
        }
        loadText(text, source: "剪贴板", autoRun: false)
    }
    func loadText(_ text: String, source: String, autoRun: Bool) {
        original.string = text; result.string = ""; copyButton.isEnabled = false
        inputLabel.stringValue = "原文 · \(source)"
        capturedText = text; showWindow()
        status("已读取 \(text.count) 个字符。")
        if autoRun { run() }
    }

    @objc func run() {
        guard !busy else { return }
        let source = original.string
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status("先选中或粘贴一段文字。", error: true); return }
        guard source.count <= 18000 else { status("一次最多处理 18,000 个字符，请分段选取。", error: true); return }
        let key: String
        do {
            guard let saved = try KeyStore.read(), !saved.isEmpty else { status("请先在 DeepSeek 设置中填入 API Key。", error: true); showSettings(); return }
            key = saved
        } catch { status(error.localizedDescription, error: true); return }
        let selectedMode = mode, selectedModel = model
        let id = UUID(); requestID = id
        result.string = ""; copyButton.isEnabled = false
        original.isEditable = false; modePicker.isEnabled = false; runButton.isEnabled = false
        cancelButton.isHidden = false; progress.startAnimation(nil)
        status("DeepSeek 正在\(selectedMode == .polish ? "润色" : selectedMode == .explain ? "解释" : "翻译")这段文字…")
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await DeepSeekClient().complete(text: source, mode: selectedMode, key: key, model: selectedModel)
                guard !Task.isCancelled, self.requestID == id else { return }
                self.result.string = response.text
                self.copyButton.isEnabled = response.warning == nil
                self.status(response.warning ?? "已完成。核对预览后，可复制结果回到浏览器。", error: response.warning != nil)
            } catch {
                guard self.requestID == id else { return }
                if Task.isCancelled { self.status("已取消，原文已保留。") }
                else if let e = error as? URLError, e.code == .timedOut { self.status("请求超时，请稍后重试或缩短段落。", error: true) }
                else if error is URLError { self.status("网络连接失败，请检查网络后重试。", error: true) }
                else { self.status(error.localizedDescription, error: true) }
            }
            if self.requestID == id { self.finishRun() }
        }
    }
    func finishRun() { activeTask = nil; progress.stopAnimation(nil); cancelButton.isHidden = true; runButton.isEnabled = true; original.isEditable = true; modePicker.isEnabled = true }
    @objc func cancel() { requestID = UUID(); activeTask?.cancel(); finishRun(); status("已取消，原文已保留。") }
    @objc func copyResult() {
        guard copyButton.isEnabled, !result.string.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result.string, forType: .string)
        status("结果已复制。返回 Overleaf，确认要替换的文字后按 ⌘V。")
    }

    func registerShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, pointer in
            guard let pointer, let event else { return noErr }
            let controller = Unmanaged<AssistantApp>.fromOpaque(pointer).takeUnretainedValue()
            var hotID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotID) == noErr else { return noErr }
            let actionID = hotID.id
            DispatchQueue.main.async {
                switch actionID {
                case 2: controller.captureReadingSelection()
                case 3: controller.readBrowserPaper()
                default: controller.captureSelection()
                }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let id = EventHotKeyID(signature: 0x41504453, id: 1)
        let outcome = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if outcome != noErr { status("快捷键已被其他应用占用；可通过菜单栏或右键“服务”使用。", error: true) }
        for (code, actionID) in [(kVK_ANSI_D, UInt32(2)), (kVK_ANSI_R, UInt32(3))] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x41504453, id: actionID), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { readingHotKeys.append(reference) }
            else { status("阅读快捷键未注册成功，可通过“论文阅读”按钮使用。", error: true) }
        }
    }
    @objc func requestAccessibility() {
        let alert = NSAlert()
        alert.messageText = "允许读取你主动选中的文字"
        alert.informativeText = "全局快捷键需要 macOS 的“辅助功能”权限，才能读取你选中的文字或当前论文地址。仅在你发起润色、选段提问或读取浏览器论文时触发。\n\n请在系统设置 → 隐私与安全性 → 辅助功能中，为“学术助手”打开开关。也可以使用复制粘贴和导入 PDF。"
        alert.addButton(withTitle: "打开系统设置"); alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    @objc func captureSelection() {
        beginSelectionCapture(reading: false)
    }
    @objc func captureReadingSelection() {
        beginSelectionCapture(reading: true)
    }
    func deliverSelection(_ text: String, from app: NSRunningApplication) {
        if captureForReading {
            showReader()
            reader?.acceptSelection(text, source: app.localizedName ?? "浏览器", sourceURL: capturedDocumentURL)
        } else {
            modePicker.selectedSegment = 0; modeChanged(); loadText(text, source: app.localizedName ?? "浏览器", autoRun: true)
        }
    }
    func beginSelectionCapture(reading: Bool) {
        guard !busy else { showWindow(); status("请等待当前处理结束，或先取消。", error: true); return }
        captureID = UUID(); captureForReading = reading
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            if reading { showReader(); reader?.quotePDF() } else { showWindow() }
            return
        }
        externalApp = front
        guard AXIsProcessTrusted() else { showWindow(); status("首次使用快捷键需要点击“启用选文快捷键”授权。也可先 ⌘C，再点击“粘贴文字”。", error: true); return }
        capturedDocumentURL = BrowserPaperSource.documentURL(front)?.absoluteString
        let appElement = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.4)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused {
            let element = focused as! AXUIElement
            var selected: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
               let text = selected as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deliverSelection(text, from: front); return
            }
        }
        let id = UUID(); captureID = id
        waitForModifiers(front: front, id: id, attempt: 0)
    }
    func waitForModifiers(front: NSRunningApplication, id: UUID, attempt: Int) {
        guard id == captureID else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            if attempt < 30 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitForModifiers(front: front, id: id, attempt: attempt + 1) } }
            else { showWindow(); status("请松开快捷键后再试。", error: true) }
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier else { showWindow(); status("当前窗口已改变，请回到原文重新选取。", error: true); return }
        let clipboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (clipboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { values[type] = data } }
            return values
        }
        let initialCount = clipboard.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        awaitClipboard(front: front, id: id, saved: saved, initialCount: initialCount, attempt: 0)
    }
    func awaitClipboard(front: NSRunningApplication, id: UUID, saved: [[NSPasteboard.PasteboardType: Data]], initialCount: Int, attempt: Int) {
        guard id == captureID else { return }
        let pb = NSPasteboard.general
        if pb.changeCount != initialCount {
            let text = pb.string(forType: .string)
            // Restore the clipboard only during this capture, before displaying the result window.
            pb.clearContents()
            let items = saved.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { showWindow(); status("没有读取到可复制的文字。扫描 PDF 可导入论文阅读，并开启“同时读取图表”。", error: true); return }
            deliverSelection(text, from: front)
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.awaitClipboard(front: front, id: id, saved: saved, initialCount: initialCount, attempt: attempt + 1) }
        } else { showWindow(); status("没有检测到选中文字。请重新选择；也可先按 ⌘C，再点击“粘贴文字”。", error: true) }
    }

    @objc func polishSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard !busy else { error.pointee = "请等待当前请求完成。"; return }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { error.pointee = "请先选中文字。"; return }
        modePicker.selectedSegment = 0; modeChanged(); loadText(text, source: "系统服务", autoRun: true)
    }
    @objc func readSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { error.pointee = "请先选中文字。"; return }
        showReader(); reader?.acceptSelection(text, source: "系统服务", sourceURL: nil)
    }

    @objc func showSettings() {
        if let settingsWindow { NSApp.activate(ignoringOtherApps: true); settingsWindow.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "连接 DeepSeek"; w.isReleasedWhenClosed = false; w.center(); settingsWindow = w
        keyField = NSSecureTextField(); keyField.placeholderString = "粘贴 DeepSeek API Key（已有密钥时可留空）"; keyField.setAccessibilityLabel("DeepSeek API Key")
        modelPicker = NSPopUpButton(); modelPicker.addItems(withTitles: ["deepseek-flash", "deepseek-v4-pro"]); modelPicker.selectItem(withTitle: model)
        saveButton = button("保存并验证连接", self, #selector(saveSettings))
        settingsStatus = label("密钥保存在此 Mac 的钥匙串中，不写入普通文件。")
        settingsStatus.textColor = .secondaryLabelColor
        let keyLink = button("打开 DeepSeek API 平台", self, #selector(openPlatform))
        let description = label("填一次密钥，以后选中文字即可使用。API 按 DeepSeek 开放平台的用量规则计费。", size: 14)
        let footer = label("连接地址：https://api.deepseek.com\n验证连接只读取模型列表；发起润色时才发送所选文字。", size: 12)
        footer.textColor = .secondaryLabelColor
        let row = NSStackView(views: [saveButton, spacer(), keyLink]); row.orientation = .horizontal
        let stack = NSStackView(views: [label("把 DeepSeek 接到你的写作流程。", size: 21, weight: .semibold), description, label("API Key", weight: .semibold), keyField, label("模型", weight: .semibold), modelPicker, row, settingsStatus, footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 24)])
        for view in [keyField!, row, settingsStatus!] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
    }
    @objc func openPlatform() { NSWorkspace.shared.open(URL(string: "https://platform.deepseek.com/api_keys")!) }
    @objc func saveSettings() {
        guard validationTask == nil else { return }
        var key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { key = (try? KeyStore.read()) ?? "" }
        guard !key.isEmpty, !key.contains("\n"), !key.contains(" ") else { settingsStatus.stringValue = "请输入完整的 API Key。"; return }
        let selected = modelPicker.titleOfSelectedItem ?? "deepseek-flash"
        keyField.isEnabled = false; saveButton.isEnabled = false; settingsStatus.stringValue = "正在验证 DeepSeek 连接…"
        validationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let models = try await DeepSeekClient().validate(key: key)
                guard !Task.isCancelled else { return }
                guard models.contains(selected) else { throw AssistantFailure(message: "该密钥无法使用 \(selected)。请检查账号支持的模型。") }
                try KeyStore.save(key)
                UserDefaults.standard.set(selected, forKey: "deepseekModel")
                self.keyField.stringValue = ""
                self.settingsStatus.stringValue = "连接成功，密钥已保存。可以关闭此窗口开始使用。"
                self.status("DeepSeek 已连接。选取一段文字即可开始。")
            } catch { self.settingsStatus.stringValue = error is URLError ? "连接失败，请检查网络后重试。" : error.localizedDescription }
            self.keyField.isEnabled = true; self.saveButton.isEnabled = true; self.validationTask = nil
        }
    }
    func showDemo() {
        original.string = #"The results shows that the proposed method have a lower estimation error under the same experimental conditions. As shown in Eq. \eqref{eq:model}, the response is proportional to $x^2$."#
        result.string = #"The results show that the proposed method has a lower estimation error under the same experimental conditions. As shown in Eq. \eqref{eq:model}, the response is proportional to $x^2$."#
        inputLabel.stringValue = "原文 · 演示样例"
        copyButton.isEnabled = true
        status("界面演示：右侧为预先写好的示例，尚未调用 DeepSeek API。")
    }
}

@main
struct Launcher {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let controller = AssistantApp()
        app.delegate = controller
        app.run()
        withExtendedLifetime(controller) {}
    }
}
