import Cocoa
import WebKit
import UniformTypeIdentifiers

@MainActor
final class PaperIndexController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, WKNavigationDelegate {
    weak var owner: AssistantApp?
    let store: PaperIndexStore
    var window: NSWindow!
    let searchField = NSSearchField()
    let table = NSTableView()
    let titleField = NSTextField()
    let linkField = NSTextField()
    let tagsField = NSTextField()
    let briefView = NSTextView()
    let archiveToggle = NSButton(checkboxWithTitle: "查看已归档", target: nil, action: nil)
    let countLabel = label("", size: 12)
    let statusLabel = label("", size: 12)
    var graphView: WKWebView!
    var memoryView: WKWebView!
    let tabs = NSTabView()
    let questionField = NSTextField()
    let scopeLabel = label("全部未归档论文", size: 12)
    let memoryDepth = NSPopUpButton()
    var localSearchButton: NSButton!
    var copyMemoryButton: NSButton!
    var exportMemoryButton: NSButton!
    var askButton: NSButton!
    var relationButton: NSButton!
    var newConversationButton: NSButton!
    var askCurrentButton: NSButton!
    var memoryTask: Task<Void, Never>?
    var memoryRequest = UUID()
    var memoryTurns: [MemoryTurn] = []
    var memoryFocus: UUID?
    var relationStore: PaperRelationStore?

    var archiveButton: NSButton!
    var saveButton: NSButton!
    var openButton: NSButton!
    var readingButton: NSButton!
    var visible: [IndexedPaper] = []
    var selectedID: UUID?
    var reloading = false
    var selected: IndexedPaper? { store.papers.first { $0.id == selectedID } }

    init(owner: AssistantApp, store: PaperIndexStore) {
        self.owner = owner; self.store = store
        super.init(); build(); reload()
    }
    func build() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 790), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "论文索引 · 学术助手"; window.minSize = NSSize(width: 1020, height: 700)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        let header = NSStackView(views: [label("论文索引", size: 18, weight: .semibold), spacer(), button("论文阅读", owner!, #selector(AssistantApp.showReader)), button("模型设置", owner!, #selector(AssistantApp.showSettings))])
        header.orientation = .horizontal
        searchField.placeholderString = "搜索标题、主题或摘要关键词…"
        searchField.setAccessibilityLabel("搜索论文索引"); searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        archiveToggle.target = self; archiveToggle.action = #selector(changeArchiveFilter)
        let tools = NSStackView(views: [searchField, archiveToggle, button("收藏浏览器论文", self, #selector(collectBrowser)), button("手动添加", self, #selector(addPaper)), button("导出索引", self, #selector(exportIndex))])
        tools.orientation = .horizontal; tools.spacing = 8
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("paper")); column.title = "我的论文"; column.width = 370
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 78; table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self; table.delegate = self; table.setAccessibilityLabel("论文索引列表")
        let listScroll = NSScrollView(); listScroll.documentView = table; listScroll.hasVerticalScroller = true; listScroll.borderType = .bezelBorder
        let left = NSStackView(views: [countLabel, listScroll]); left.orientation = .vertical; left.alignment = .leading; left.spacing = 8
        left.widthAnchor.constraint(equalToConstant: 360).isActive = true
        listScroll.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true

        titleField.placeholderString = "论文标题"; titleField.setAccessibilityLabel("索引论文标题")
        linkField.placeholderString = "https://…（可留空）"; linkField.setAccessibilityLabel("论文原文链接")
        tagsField.placeholderString = "例如：触觉感知、机器人、力感知"; tagsField.setAccessibilityLabel("论文主题标签")
        tagsField.toolTip = "标签来自本机关键词提取，可用逗号分隔后修改。卡片不保存 PDF 或全文。"
        briefView.isRichText = false; briefView.font = .systemFont(ofSize: 15); briefView.textContainerInset = NSSize(width: 12, height: 10)
        briefView.isVerticallyResizable = true; briefView.isHorizontallyResizable = false
        briefView.autoresizingMask = [.width]; briefView.textContainer?.widthTracksTextView = true
        briefView.setAccessibilityLabel("论文简短摘要")
        let briefScroll = NSScrollView(); briefScroll.documentView = briefView; briefScroll.hasVerticalScroller = true; briefScroll.borderType = .bezelBorder
        briefScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        saveButton = button("保存卡片", self, #selector(saveCard)); saveButton.bezelColor = .systemTeal
        openButton = button("打开原文", self, #selector(openSource))
        readingButton = button("继续精读", self, #selector(continueReading))
        askCurrentButton = button("问这篇", self, #selector(askCurrent))
        archiveButton = button("移到已归档", self, #selector(archivePaper))
        let actions = NSStackView(views: [saveButton, openButton, readingButton, askCurrentButton, spacer(), archiveButton]); actions.orientation = .horizontal; actions.spacing = 6
        briefView.toolTip = "摘自已有中文导读；手动保存后，自动同步会保留你的编辑。"
        let card = NSStackView(views: [label("论文标题", weight: .semibold), titleField, label("原文链接", weight: .semibold), linkField, label("主题标签", weight: .semibold), tagsField, label("简短摘要 · 最多 600 字符", weight: .semibold), briefScroll, actions])
        card.orientation = .vertical; card.alignment = .leading; card.spacing = 10
        for v in [titleField, linkField, tagsField, briefScroll, actions] { v.widthAnchor.constraint(equalTo: card.widthAnchor).isActive = true }
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        graphView = WKWebView(frame: .zero, configuration: config); graphView.navigationDelegate = self
        let cardTab = NSTabViewItem(identifier: "card"); cardTab.label = "论文卡片"; cardTab.view = card; tabs.addTabViewItem(cardTab)
        let graphTab = NSTabViewItem(identifier: "graph"); graphTab.label = "关联图谱"
        relationButton = button("分析这篇的关联", self, #selector(analyzeRelations))
        relationButton.toolTip = "使用已有摘要、导读和笔记，调用所选模型服务整理内容关联并保存简短依据。未分析时显示共同标签。"
        let graphTools = NSStackView(views: [relationButton, spacer()]); graphTools.orientation = .horizontal
        let graphColumn = NSStackView(views: [graphTools, graphView!]); graphColumn.orientation = .vertical; graphColumn.spacing = 8
        for v in [graphTools, graphView!] { v.widthAnchor.constraint(equalTo: graphColumn.widthAnchor).isActive = true }
        graphTab.view = graphColumn; tabs.addTabViewItem(graphTab)
        let memoryConfig = WKWebViewConfiguration(); memoryConfig.websiteDataStore = .nonPersistent(); memoryConfig.defaultWebpagePreferences.allowsContentJavaScript = false
        memoryView = WKWebView(frame: .zero, configuration: memoryConfig); memoryView.navigationDelegate = self
        questionField.placeholderString = "描述你记得的论文，或继续追问、比较…"; questionField.setAccessibilityLabel("论文库问题")
        questionField.target = self; questionField.action = #selector(askMemory)
        askButton = button("DeepSeek 回答", self, #selector(askMemory)); askButton.bezelColor = .systemTeal
        newConversationButton = button("新对话", self, #selector(newConversation))
        let scopeRow = NSStackView(views: [scopeLabel, spacer(), newConversationButton]); scopeRow.orientation = .horizontal
        let questionRow = NSStackView(views: [questionField, askButton]); questionRow.orientation = .horizontal; questionRow.spacing = 8
        questionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        memoryDepth.addItems(withTitles: ["省量 · 最多 3 篇", "深入 · 最多 6 篇"])
        memoryDepth.setAccessibilityLabel("论文库分析深度")
        memoryDepth.toolTip = "省量：每篇最多 2,000 字符摘录；深入：每篇最多 5,000 字符。另附问题、简短历史和回答规则。没有 PDF 全文。"
        localSearchButton = button("本地找论文", self, #selector(findMemoryLocally))
        copyMemoryButton = button("复制提问材料", self, #selector(copyMemoryContext))
        exportMemoryButton = button("导出材料", self, #selector(exportMemoryContext))
        copyMemoryButton.toolTip = "本地整理，可粘贴到 Claude Code、Codex、ChatGPT 或其他工具；不调用 DeepSeek。"
        let memoryTools = NSStackView(views: [memoryDepth, localSearchButton, spacer(), copyMemoryButton, exportMemoryButton]); memoryTools.orientation = .horizontal; memoryTools.spacing = 6
        let privacy = label("本地检索不耗额度；回答使用窗口标题中的服务。复制材料可交给其他工具。", size: 11); privacy.textColor = .secondaryLabelColor
        let memoryColumn = NSStackView(views: [scopeRow, memoryView!, memoryTools, questionRow, privacy]); memoryColumn.orientation = .vertical; memoryColumn.spacing = 10
        for v in [scopeRow, memoryView!, memoryTools, questionRow, privacy] { v.widthAnchor.constraint(equalTo: memoryColumn.widthAnchor).isActive = true }
        memoryView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let memoryTab = NSTabViewItem(identifier: "memory"); memoryTab.label = "问论文库"; memoryTab.view = memoryColumn; tabs.addTabViewItem(memoryTab)
        memoryView.loadHTMLString(PaperMemoryHTML.conversation([]), baseURL: nil)
        let columns = NSStackView(views: [left, tabs]); columns.orientation = .horizontal; columns.spacing = 18
        tabs.widthAnchor.constraint(equalTo: columns.widthAnchor, constant: -378).isActive = true
        left.heightAnchor.constraint(equalTo: columns.heightAnchor).isActive = true
        listScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        tabs.heightAnchor.constraint(equalTo: columns.heightAnchor).isActive = true
        let stack = NSStackView(views: [header, tools, columns, statusLabel]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -18)])
        for v in [header, tools, columns, statusLabel] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        columns.setContentHuggingPriority(.defaultLow, for: .vertical)
        statusLabel.textColor = .secondaryLabelColor
    }
    func show() { reload(); owner?.refreshServiceUI(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visible.indices.contains(row) else { return nil }
        let paper = visible[row]
        let text = NSTextField(wrappingLabelWithString: paper.title + "\n" + (paper.tags.isEmpty ? "暂无主题 · 可编辑卡片" : paper.tags.prefix(4).joined(separator: " · ")))
        text.font = .systemFont(ofSize: 13); text.maximumNumberOfLines = 3
        let cell = NSTableCellView(); cell.textField = text; cell.addSubview(text); text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading else { return }
        selectedID = visible.indices.contains(table.selectedRow) ? visible[table.selectedRow].id : nil
        display()
    }
    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === searchField { reload() }
    }
    @objc func changeArchiveFilter() { selectedID = nil; reload() }
    func reload(select id: UUID? = nil) {
        if let id { selectedID = id }
        visible = store.search(searchField.stringValue, archived: archiveToggle.state == .on)
        reloading = true; table.reloadData()
        let row = visible.firstIndex { $0.id == selectedID } ?? (visible.isEmpty ? nil : 0)
        selectedID = row.map { visible[$0].id }
        if let row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } else { table.deselectAll(nil) }
        reloading = false
        countLabel.stringValue = "\(visible.count) 篇\(archiveToggle.state == .on ? "已归档" : "论文") · 共 \(store.papers.filter { !$0.archived }.count) 篇在索引中"
        display()
    }
    func display() {
        let paper = selected
        titleField.stringValue = paper?.title ?? ""; linkField.stringValue = paper?.sourceURL ?? ""
        tagsField.stringValue = paper?.tags.joined(separator: "、") ?? ""; briefView.string = paper?.brief ?? ""
        for field in [titleField, linkField, tagsField] { field.isEnabled = paper != nil }; briefView.isEditable = paper != nil
        saveButton.isEnabled = paper != nil; openButton.isEnabled = paper != nil; archiveButton.isEnabled = paper != nil
        readingButton.isEnabled = paper?.readingID != nil
        openButton.title = paper?.sourceURL == nil ? "按标题找原文" : "打开原文"
        archiveButton.title = paper?.archived == true ? "恢复到索引" : "移到已归档"
        askCurrentButton.isEnabled = paper != nil && memoryTask == nil
        relationButton.isEnabled = paper != nil && memoryTask == nil
        renderGraph()
        statusLabel.stringValue = paper.map { "最近阅读：\(DateFormatter.localizedString(from: $0.lastReadAt, dateStyle: .medium, timeStyle: .none)) · 修改后点击“保存卡片”" } ?? "还没有匹配结果。试试更短的关键词，或收藏一篇论文。"
    }
    @objc func saveCard() {
        guard var paper = selected else { return }
        paper.title = titleField.stringValue; paper.sourceURL = linkField.stringValue
        paper.tags = tagsField.stringValue.components(separatedBy: CharacterSet(charactersIn: ",，、;；\n"))
        paper.brief = briefView.string; paper.manuallyEdited = true
        do { try store.update(paper); reload(select: paper.id); statusLabel.stringValue = "卡片已保存，主题图谱已更新。" }
        catch { statusLabel.stringValue = error.localizedDescription }
    }
    @objc func archivePaper() {
        guard var paper = selected else { return }
        paper.archived.toggle()
        do { try store.update(paper); reload(); statusLabel.stringValue = paper.archived ? "已移到已归档，可勾选“查看已归档”恢复；原阅读记录保留。" : "已恢复到论文索引。" }
        catch { statusLabel.stringValue = error.localizedDescription }
    }
    @objc func openSource() {
        guard let paper = selected else { return }
        if let raw = PaperIndexText.validURL(paper.sourceURL), let url = URL(string: raw) { NSWorkspace.shared.open(url) }
        else {
            var url = URLComponents(string: "https://scholar.google.com/scholar")!
            url.queryItems = [URLQueryItem(name: "q", value: paper.title)]
            if let url = url.url { NSWorkspace.shared.open(url) }
        }
    }
    @objc func continueReading() {
        guard let id = selected?.readingID else { return }
        owner?.showReader()
        if let reader = owner?.reader, let record = reader.papers.first(where: { $0.id == id }) { reader.display(record) }
        else { statusLabel.stringValue = "未找到本地阅读记录，可通过“打开原文”重新访问。" }
    }
    @objc func addPaper() { addDialog(title: "", url: "") }
    @objc func collectBrowser() {
        let browser = owner?.lastBrowser
        guard let browser, let url = BrowserPaperSource.documentURL(browser) else {
            statusLabel.stringValue = "先在浏览器打开论文，再来收藏；也可以手动添加标题与链接。"; return
        }
        addDialog(title: BrowserPaperSource.documentTitle(browser) ?? "", url: url.absoluteString)
    }
    func addDialog(title: String, url: String) {
        let alert = NSAlert(); alert.messageText = "收藏论文，不下载 PDF"; alert.informativeText = "确认论文名称与链接。之后可补上主题与一句话摘要。"
        let titleInput = NSTextField(string: title); titleInput.placeholderString = "论文名称"; titleInput.setAccessibilityLabel("新增论文名称")
        let urlInput = NSTextField(string: url); urlInput.placeholderString = "论文链接（可留空）"; urlInput.setAccessibilityLabel("新增论文链接")
        let stack = NSStackView(views: [titleInput, urlInput]); stack.orientation = .vertical; stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 500, height: 72)
        for field in [titleInput, urlInput] { field.widthAnchor.constraint(equalToConstant: 500).isActive = true }
        alert.accessoryView = stack; alert.addButton(withTitle: "收藏"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                let raw = urlInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty && PaperIndexText.validURL(raw) == nil { throw AssistantFailure(message: "链接格式不正确，请使用完整的 http/https 地址。") }
                let paper = try self.store.collect(title: titleInput.stringValue, sourceURL: raw.isEmpty ? nil : raw)
                self.searchField.stringValue = ""; self.archiveToggle.state = paper.archived ? .on : .off
                self.reload(select: paper.id); self.statusLabel.stringValue = "已收录论文卡片，没有下载 PDF，也没有调用模型。"
            } catch { self.statusLabel.stringValue = error.localizedDescription }
        }
        window.makeFirstResponder(titleInput)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.request.url?.scheme == "paper-index", let raw = action.request.url?.host, let id = UUID(uuidString: raw), store.papers.contains(where: { $0.id == id && !$0.archived }) {
            searchField.stringValue = ""; archiveToggle.state = .off; reload(select: id); tabs.selectTabViewItem(withIdentifier: "card"); decisionHandler(.cancel)
        } else { decisionHandler(action.navigationType == .linkActivated ? .cancel : .allow) }
    }
    @objc func exportIndex() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]; panel.nameFieldStringValue = "我的论文索引.md"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.store.markdown().write(to: url, atomically: true, encoding: .utf8); self.statusLabel.stringValue = "已导出论文卡片，不包含 PDF、全文或阅读对话。" }
            catch { self.statusLabel.stringValue = error.localizedDescription }
        }
    }
}
