import Cocoa
import PDFKit
import WebKit
import UniformTypeIdentifiers

@MainActor
final class PaperReaderController: NSObject, NSWindowDelegate, NSTextViewDelegate, WKNavigationDelegate {
    weak var owner: AssistantApp?
    let library: PaperLibrary
    var window: NSWindow!
    var papers: [PaperRecord] = []
    var current: PaperRecord?
    var picker = NSPopUpButton()
    var pdfView = PDFView()
    var tabs = NSTabView()
    var overviewView: WKWebView!
    var conversationView: WKWebView!
    var notesView = NSTextView()
    var passageView = NSTextView()
    var questionView = NSTextView()
    var titleLabel = label("从浏览器接入一篇论文，或导入 PDF。", size: 14, weight: .medium)
    var statusLabel = label("导读和问答会标注页码；点击页码可回到原文。", size: 12)
    var pageField = NSTextField(string: "1")
    var scopeField = NSTextField(string: "")
    var visionToggle = NSButton(checkboxWithTitle: "同时读取图表", target: nil, action: nil)
    var generateButton: NSButton!
    var askButton: NSButton!
    var cancelButton: NSButton!
    var progress = NSProgressIndicator()
    var busyControls: [NSControl] = []
    var activeTask: Task<Void, Never>?
    var operationID = UUID()
    var noteSave: DispatchWorkItem?
    var loadingNotes = false

    init(owner: AssistantApp) throws {
        self.owner = owner
        library = try PaperLibrary()
        super.init()
        build()
        papers = try library.all()
        refreshPicker()
        if let first = papers.first { display(first) } else { renderEmpty() }
    }
    var busy: Bool { activeTask != nil }
    func webView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        return view
    }
    func textBox(_ text: NSTextView, label name: String, height: CGFloat? = nil, editable: Bool = true) -> NSScrollView {
        text.isRichText = false; text.isEditable = editable; text.isSelectable = true
        text.font = .systemFont(ofSize: 14)
        text.textContainerInset = NSSize(width: 10, height: 9)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        text.setAccessibilityLabel(name)
        let scroll = NSScrollView(); scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        if let height { scroll.heightAnchor.constraint(equalToConstant: height).isActive = true }
        return scroll
    }
    func build() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 850), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "论文阅读 · 学术助手"; window.minSize = NSSize(width: 1040, height: 730)
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        let header = NSStackView(views: [label("先读懂全貌，再追问细节。", size: 24, weight: .semibold), spacer(), button("写作润色", self, #selector(openWriting))])
        header.orientation = .horizontal
        let hint = label("浏览器论文 ⌃⌥⌘R  ·  选中段落追问 ⌃⌥⌘D  ·  中文导读、问答和笔记自动保存在此 Mac", size: 12)
        hint.textColor = .secondaryLabelColor
        picker.target = self; picker.action = #selector(selectPaper); picker.setAccessibilityLabel("我的论文")
        picker.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        let renameButton = button("重命名", self, #selector(renamePaper))
        let libraryRow = NSStackView(views: [label("我的论文", weight: .semibold), picker, renameButton, spacer(), button("导出阅读笔记", self, #selector(exportReading))])
        libraryRow.orientation = .horizontal; libraryRow.spacing = 10
        let importButton = button("导入 PDF", self, #selector(importPDF))
        let linkButton = button("粘贴论文链接", self, #selector(importLink))
        let browserButton = button("从浏览器读取", self, #selector(fromBrowser))
        visionToggle.state = .on
        visionToggle.toolTip = "Flash 可读取本轮范围内最多 80 页图像。长文默认仅用全文文字；填写解读页码后可开启图表。Pro 仅处理文字。"
        generateButton = button("生成中文导读", self, #selector(summarize))
        generateButton.bezelColor = .systemTeal
        cancelButton = button("取消", self, #selector(cancel)); cancelButton.isHidden = true
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let actions = NSStackView(views: [importButton, linkButton, browserButton, visionToggle, spacer(), progress, cancelButton, generateButton])
        actions.orientation = .horizontal; actions.spacing = 8
        titleLabel.maximumNumberOfLines = 2
        titleLabel.setAccessibilityLabel("论文范围")
        scopeField.placeholderString = "全部，或 20-35"
        scopeField.setAccessibilityLabel("解读范围")
        scopeField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let scopeHint = label("留空读全文；长文默认仅文字。读图表时填写页码，并勾选“同时读取图表”。", size: 11)
        scopeHint.textColor = .secondaryLabelColor
        let scopeRow = NSStackView(views: [label("解读范围", size: 12), scopeField, scopeHint, spacer()])
        scopeRow.orientation = .horizontal; scopeRow.spacing = 10
        pageField.setAccessibilityLabel("跳转到 PDF 页"); pageField.alignment = .center
        pageField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let jump = button("跳转", self, #selector(jumpPage))
        let quote = button("用选中段落提问", self, #selector(quotePDF))
        let pageBar = NSStackView(views: [label("原文 · PDF 页", size: 12), pageField, jump, spacer(), quote])
        pageBar.orientation = .horizontal; pageBar.spacing = 6
        pdfView.autoScales = true; pdfView.displayMode = .singlePageContinuous; pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor
        let pdfColumn = NSStackView(views: [pageBar, pdfView]); pdfColumn.orientation = .vertical; pdfColumn.spacing = 8; pdfColumn.alignment = .leading
        pageBar.widthAnchor.constraint(equalTo: pdfColumn.widthAnchor).isActive = true
        pdfView.widthAnchor.constraint(equalTo: pdfColumn.widthAnchor).isActive = true
        pdfView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        overviewView = webView(); conversationView = webView()
        let overviewTab = NSTabViewItem(identifier: "overview"); overviewTab.label = "中文导读"; overviewTab.view = overviewView
        tabs.addTabViewItem(overviewTab)
        let passageScroll = textBox(passageView, label: "本轮引用段落", height: 68)
        let questionScroll = textBox(questionView, label: "要问的问题", height: 70)
        askButton = button("发送问题", self, #selector(ask)); askButton.keyEquivalent = "\r"; askButton.keyEquivalentModifierMask = [.command]; askButton.bezelColor = .systemTeal
        let sendRow = NSStackView(views: [button("清除引用", self, #selector(clearPassage)), spacer(), label("⌘↩ 发送", size: 11), askButton]); sendRow.orientation = .horizontal
        let quickNames = ["解释这段", "推导公式", "实验说明什么", "结论有何局限"]
        let quickButtons = quickNames.enumerated().map { index, name -> NSButton in
            let b = button(name, self, #selector(quickAsk(_:))); b.tag = index; return b
        }
        let quickRow = NSStackView(views: quickButtons); quickRow.orientation = .horizontal; quickRow.spacing = 5
        let chatColumn = NSStackView(views: [conversationView, label("本轮引用段落（可粘贴或编辑）", size: 11), passageScroll, quickRow, questionScroll, sendRow])
        chatColumn.orientation = .vertical; chatColumn.alignment = .leading; chatColumn.spacing = 8
        for view in [conversationView!, passageScroll, quickRow, questionScroll, sendRow] { view.widthAnchor.constraint(equalTo: chatColumn.widthAnchor).isActive = true }
        conversationView.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        let chatTab = NSTabViewItem(identifier: "chat"); chatTab.label = "细读问答"; chatTab.view = chatColumn; tabs.addTabViewItem(chatTab)
        let notesScroll = textBox(notesView, label: "我的阅读笔记"); notesView.delegate = self
        let noteTab = NSTabViewItem(identifier: "notes"); noteTab.label = "我的笔记"; noteTab.view = notesScroll; tabs.addTabViewItem(noteTab)
        let columns = NSStackView(views: [pdfColumn, tabs]); columns.orientation = .horizontal; columns.distribution = .fillEqually; columns.spacing = 16
        statusLabel.textColor = .secondaryLabelColor; statusLabel.maximumNumberOfLines = 2
        let privacy = label("导入与笔记仅存本机；开始导读或提问时，本篇材料发送至 DeepSeek。相关工作仅依据论文自身引文。", size: 11)
        privacy.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [header, hint, libraryRow, actions, titleLabel, scopeRow, columns, statusLabel, privacy])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16)])
        for view in [header, libraryRow, actions, titleLabel, scopeRow, columns, statusLabel] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        columns.setContentHuggingPriority(.defaultLow, for: .vertical)
        busyControls = [picker, renameButton, importButton, linkButton, browserButton, scopeField, visionToggle, generateButton, askButton, quote] + quickButtons
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { flushNotes(); sender.orderOut(nil); return false }
    @objc func openWriting() { owner?.showWindow() }
    @objc func fromBrowser() { owner?.readBrowserPaper() }
    func status(_ text: String, error: Bool = false) { statusLabel.stringValue = text; statusLabel.textColor = error ? .systemRed : .secondaryLabelColor }
    func refreshPicker() {
        picker.removeAllItems()
        if papers.isEmpty { picker.addItem(withTitle: "尚未导入论文") }
        else { picker.addItems(withTitles: papers.map { ($0.isExcerpt ? "段落 · " : "") + String($0.title.prefix(75)) }) }
        if let id = current?.id, let index = papers.firstIndex(where: { $0.id == id }) { picker.selectItem(at: index) }
    }
    func persist(_ record: PaperRecord) throws {
        var saved = record; saved.updatedAt = Date(); try library.save(saved)
        current = saved; papers = try library.all(); refreshPicker()
    }
    func display(_ record: PaperRecord) {
        let selected = current?.id == record.id ? current! : record
        flushNotes(); let record = selected; current = record
        scopeField.stringValue = ""
        visionToggle.state = record.pages.count > 80 ? .off : .on
        pdfView.document = record.isExcerpt ? nil : PDFDocument(url: library.pdfURL(record.id))
        passageView.string = record.isExcerpt ? record.pages.first?.text ?? "" : ""
        questionView.string = ""
        loadingNotes = true; notesView.string = record.notes; loadingNotes = false
        let readable = record.pages.filter { $0.text.count > 40 }.count
        titleLabel.stringValue = "\(record.title)\n" + (record.isExcerpt ? "仅选中段落 · 尚未导入全文，不推断全篇实验和结论" : "共 \(record.pages.count) 页 · 可提取文字 \(readable)/\(record.pages.count) 页 · \(record.characterCount) 字符 · 原文完整保留")
        render(); refreshPicker()
        status(record.isExcerpt ? "可直接围绕段落提问；若要理解整篇，请导入 PDF。" : (record.pages.count > 80 ? "长文已完整导入。默认用全文文字导读；图表精读请填写页码范围并开启图表。" : "论文已就绪。生成中文导读，或选中左侧原文开始细读。"))
    }
    func renderEmpty() {
        overviewView.loadHTMLString(ReadingHTML.document("<h1>从一篇论文开始</h1><p>在浏览器 PDF 页面按 <strong>⌃⌥⌘R</strong>，或点击“导入 PDF”。</p><p>导读会整理核心想法、问题与相关工作、挑战与贡献、方法、实验、结果和局限。</p><p>在浏览器选中段落后按 <strong>⌃⌥⌘D</strong>，即可打开中文细读问答。</p>"), baseURL: nil)
        conversationView.loadHTMLString(ReadingHTML.document("<p class='empty'>选中一段文字，把不理解的地方问清楚。</p>"), baseURL: nil)
    }
    func render() {
        guard let record = current else { renderEmpty(); return }
        overviewView.loadHTMLString(ReadingHTML.document(record.summary.isEmpty ? "<h1>原文已准备好</h1><p>点击“生成中文导读”，先掌握论文的完整思路。</p><p class='meta'>事实会标注 PDF 页码。图表较多时，建议保留“同时读取图表”。</p>" : ReadingHTML.markdown(record.summary)), baseURL: nil)
        let body = record.turns.isEmpty ? "<p class='empty'>可以问：这句话是什么意思？为什么采用这个假设？实验如何支持贡献？</p>" : "<p class='meta'>最近问答在上方 · 每次带入当前论文与最近 16 轮对话</p>" + record.turns.reversed().map { turn in
            "<section class='turn'><div class='role'>你的问题</div><p class='question'>\(ReadingHTML.inline(turn.question))</p>" + (turn.passage.isEmpty ? "" : "<blockquote>\(ReadingHTML.escape(String(turn.passage.prefix(1400))))</blockquote>") + "<div class='role'>中文解读</div>\(ReadingHTML.markdown(turn.answer))</section>"
        }.joined()
        conversationView.loadHTMLString(ReadingHTML.document(body), baseURL: nil)
    }
    @objc func selectPaper() {
        guard !busy, papers.indices.contains(picker.indexOfSelectedItem) else { return }
        display(papers[picker.indexOfSelectedItem])
    }
    @objc func renamePaper() {
        guard !busy, let record = current else { return }
        let alert = NSAlert(); alert.messageText = "论文名称"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 460, height: 28)); field.stringValue = record.title
        alert.accessoryView = field; alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, var updated = self.current else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }; updated.title = String(name.prefix(300))
            do { try self.persist(updated); self.display(updated) } catch { self.status(error.localizedDescription, error: true) }
        }
        window.makeFirstResponder(field)
    }
    func textDidChange(_ notification: Notification) {
        guard !loadingNotes, notification.object as? NSTextView === notesView, var record = current else { return }
        record.notes = notesView.string; current = record
        noteSave?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.flushNotes() }; noteSave = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: job)
    }
    func flushNotes() {
        noteSave?.cancel(); noteSave = nil
        guard let current else { return }
        do { try library.save(current); if let index = papers.firstIndex(where: { $0.id == current.id }) { papers[index] = current } }
        catch { status("笔记未能保存：\(error.localizedDescription)", error: true) }
    }
    func setBusy(_ value: Bool) {
        for control in busyControls { control.isEnabled = !value }
        notesView.isEditable = !value; questionView.isEditable = !value; passageView.isEditable = !value
        cancelButton.isHidden = !value
        value ? progress.startAnimation(nil) : progress.stopAnimation(nil)
    }
    func perform(_ message: String, work: @escaping @MainActor (PaperReaderController) async throws -> Void) {
        guard !busy else { show(); status("当前处理尚未完成，可以先取消。", error: true); return }
        flushNotes(); let id = UUID(); operationID = id; setBusy(true); status(message)
        activeTask = Task { [weak self] in
            guard let self else { return }
            do { try await work(self) }
            catch {
                if self.operationID == id {
                    self.status(Task.isCancelled ? "已取消。原文、已有导读和对话均保留。" : (error is URLError ? "网络连接未完成，请检查网络后重试；现有笔记已保留。" : error.localizedDescription), error: !Task.isCancelled)
                }
            }
            if self.operationID == id { self.activeTask = nil; self.setBusy(false) }
        }
    }
    @objc func cancel() { operationID = UUID(); activeTask?.cancel(); activeTask = nil; setBusy(false); status("已取消。原文、已有导读和对话均保留。") }
    @objc func importPDF() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openURL(url)
        }
    }
    @objc func importLink() {
        guard !busy else { return }
        let alert = NSAlert(); alert.messageText = "读取论文 PDF"; alert.informativeText = "粘贴浏览器里的 PDF 链接或 arXiv 论文链接。需要登录的网站，可先下载 PDF 再导入。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 460, height: 28)); field.placeholderString = "https://…"
        if let raw = NSPasteboard.general.string(forType: .string), PaperDownload.normalizedURL(raw) != nil { field.stringValue = raw }
        alert.accessoryView = field; alert.addButton(withTitle: "读取"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let url = PaperDownload.normalizedURL(field.stringValue) else { self?.status("请输入完整的 PDF 链接。", error: true); return }
            self?.openURL(url)
        }
        window.makeFirstResponder(field)
    }
    func openURL(_ url: URL) {
        show()
        perform("正在读取论文；导入完成后可生成中文导读。") { controller in
            let (data, finalURL) = try await PaperDownload.fetch(url)
            try Task.checkCancellation()
            let library = controller.library
            let name = finalURL.pathExtension.lowercased() == "pdf" ? finalURL.deletingPathExtension().lastPathComponent : finalURL.lastPathComponent
            let record = try await Task.detached { try library.importPDF(data, name: name, sourceURL: finalURL.absoluteString) }.value
            try Task.checkCancellation()
            controller.papers = try library.all(); controller.display(record); controller.tabs.selectTabViewItem(at: 0)
        }
    }
    func acceptSelection(_ text: String, source: String, sourceURL: String?) {
        show()
        guard !busy else { status("正在处理另一项请求，请完成或取消后重新选取。", error: true); return }
        guard text.count <= 20_000 else { status("选文超过 20,000 字符。长文请直接导入 PDF。", error: true); return }
        do {
            flushNotes(); papers = try library.all()
            let record: PaperRecord
            if let matched = matchingPaper(for: text, sourceURL: sourceURL, papers: papers) { record = matched }
            else {
                record = PaperRecord(title: String(text.replacingOccurrences(of: "\n", with: " ").prefix(65)), sourceURL: sourceURL, pages: [PaperPage(number: 1, text: text)], isExcerpt: true)
                try library.save(record); papers = try library.all()
            }
            display(record); passageView.string = text
            questionView.string = "请解释这段话的核心意思、关键概念，以及它在论文中的作用。"
            tabs.selectTabViewItem(at: 1); window.makeFirstResponder(questionView)
            status(record.isExcerpt ? "已从 \(source) 取得选文。本次仅依据段落；输入问题后按 ⌘↩。" : "已关联当前论文全文。可以围绕选段连续追问，按 ⌘↩ 发送。")
        } catch { status(error.localizedDescription, error: true) }
    }
    func credentials() throws -> (String, String) {
        guard let key = try KeyStore.read(), !key.isEmpty else { owner?.showSettings(); throw AssistantFailure(message: "请先连接 DeepSeek。") }
        return (key, owner?.model ?? "deepseek-flash")
    }
    func preparedImages(_ paper: PaperRecord, pages: [PaperPage], model: String) async throws -> [(Int, Data)] {
        if paper.isExcerpt { return [] }
        if visionToggle.state != .on || model != "deepseek-flash" {
            guard pages.reduce(0, { $0 + $1.text.count }) >= 80 else { throw AssistantFailure(message: "本轮没有足够可提取的文字。请使用 Flash，指定最多 80 页并开启“同时读取图表”以阅读扫描页。") }
            return []
        }
        guard pages.count <= 80 else { throw AssistantFailure(message: "长文导读请关闭“同时读取图表”，或在“解读范围”中填写最多 80 页用于图表精读。原 PDF 始终完整保留。") }
        status("正在准备 \(pages.count) 页原文与图表…")
        let library = self.library
        let task = Task.detached { try library.images(for: paper, pages: pages.map(\.number)) }
        let images = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        try Task.checkCancellation()
        return images
    }
    @objc func summarize() {
        guard let record = current else { status("请先导入论文或选取段落。", error: true); return }
        tabs.selectTabViewItem(at: 0)
        perform("正在准备论文导读…") { controller in
            let (key, model) = try controller.credentials()
            let pages = try PaperScope.pages(controller.scopeField.stringValue, in: record)
            try PaperScope.validate(pages)
            let images = try await controller.preparedImages(record, pages: pages, model: model)
            let scope = record.isExcerpt ? "所选段落" : PaperScope.label(pages, total: record.pages.count)
            controller.status("正在整理中文导读 · \(scope)文字 + \(images.count) 页图像；长文需要更久，可随时取消。")
            let response = try await DeepSeekClient().reading(messages: PaperPrompts.messages(paper: record, images: images, pages: pages), key: key, model: model)
            let answer = "> 本轮材料：\(scope)文字；\(images.isEmpty ? "未提供页面图像" : "附 \(images.count) 页图像")。\n\n" + response
            try Task.checkCancellation()
            var updated = record
            let partial = !record.isExcerpt && pages.count < record.pages.count
            if partial { updated.turns.append(ReadingTurn(question: "章节导读：\(scope)", passage: "", answer: answer)) }
            else { updated.summary = answer }
            try controller.persist(updated); controller.render()
            if partial { controller.tabs.selectTabViewItem(at: 1) }
            controller.status(PaperPrompts.citationWarning(answer, pageCount: record.pages.count) ?? (partial ? "章节导读已保存到细读问答，全文导读仍保留。页码可点击核对。" : "中文导读已保存。点击 [p. N] 可跳到原文对应页；选择“细读问答”继续追问。"))
        }
    }
    @objc func ask() {
        guard let record = current else { status("请先导入论文或选取段落。", error: true); return }
        let question = questionView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let passage = passageView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { status("请输入想问的问题。", error: true); return }
        guard question.count <= 6000, passage.count <= 20_000 else { status("问题最多 6,000 字符，引用段落最多 20,000 字符，请缩短后重试。", error: true); return }
        tabs.selectTabViewItem(at: 1)
        perform("正在准备本轮问答…") { controller in
            let (key, model) = try controller.credentials()
            let pages = try PaperScope.pages(controller.scopeField.stringValue, in: record)
            try PaperScope.validate(pages)
            let images = try await controller.preparedImages(record, pages: pages, model: model)
            let scope = record.isExcerpt ? "所选段落" : PaperScope.label(pages, total: record.pages.count)
            controller.status("正在结合\(record.isExcerpt ? "所选段落" : scope)与最近 \(min(record.turns.count, 16)) 轮问答回答…")
            let response = try await DeepSeekClient().reading(messages: PaperPrompts.messages(paper: record, images: images, question: question, passage: passage, pages: pages), key: key, model: model, maxTokens: 6000)
            let answer = "> 本轮材料：\(scope)文字；\(images.isEmpty ? "未提供页面图像" : "附 \(images.count) 页图像")。\n\n" + response
            try Task.checkCancellation()
            var updated = record; updated.turns.append(ReadingTurn(question: question, passage: passage, answer: answer))
            try controller.persist(updated); controller.questionView.string = ""; controller.render()
            controller.status(PaperPrompts.citationWarning(answer, pageCount: record.pages.count) ?? "回答已保存。可以继续追问；输入问题后按 ⌘↩。")
        }
    }
    @objc func quickAsk(_ sender: NSButton) {
        let questions = ["请用中文解释这段话：先讲直觉，再解释术语，并说明它在论文中的作用。",
                         "请一步步解释相关公式的推导。定义每个符号，说明假设和每一步依据；原文未给出的推导请明确标为补充解释。",
                         "相关实验到底要证明什么？请对应假设、对照、指标和数值结果，解释哪些贡献被支持，哪些仍未被证明。",
                         "这项结论有哪些适用条件和证据局限？请区分作者承认的限制、实验显示的问题和你的推断。"]
        questionView.string = questions[sender.tag]; ask()
    }
    @objc func clearPassage() { passageView.string = "" }
    @objc func quotePDF() {
        guard let text = pdfView.currentSelection?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status("请先在左侧 PDF 中拖选文字。扫描页也可以直接输入页码和问题。", error: true); return
        }
        passageView.string = text; questionView.string = "请解释这段话的含义及其在论文中的作用。"
        tabs.selectTabViewItem(at: 1); window.makeFirstResponder(questionView)
    }
    @objc func jumpPage() { if let n = Int(pageField.stringValue) { goToPage(n) } }
    func goToPage(_ number: Int) {
        guard let document = pdfView.document, number >= 1, number <= document.pageCount, let page = document.page(at: number - 1) else {
            status("当前材料中没有这一页；段落阅读没有 PDF 原文。", error: true); return
        }
        pdfView.go(to: page); pageField.stringValue = String(number)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.request.url?.scheme == "paper-page", let value = action.request.url?.host, let number = Int(value) {
            goToPage(number); decisionHandler(.cancel); return
        }
        if action.navigationType == .linkActivated { decisionHandler(.cancel) } else { decisionHandler(.allow) }
    }
    @objc func exportReading() {
        flushNotes(); guard let record = current else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = String(record.title.prefix(75)).replacingOccurrences(of: "/", with: "-") + " - 阅读笔记.md"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try readingMarkdown(record).write(to: url, atomically: true, encoding: .utf8); self?.status("阅读笔记已导出，包含导读、手写笔记和完整问答。") }
            catch { self?.status(error.localizedDescription, error: true) }
        }
    }
}
