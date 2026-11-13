import Cocoa
import UniformTypeIdentifiers

extension PaperIndexController {
    func knowledgeStore() throws -> PaperRelationStore {
        if let relationStore { return relationStore }
        let created = try PaperRelationStore(root: store.root); relationStore = created; return created
    }
    func readingRecord(_ id: UUID) throws -> PaperRecord? {
        // Reuse an existing reading record; never download or create a PDF for library Q&A.
        let url = try PaperLibrary().directory(id).appendingPathComponent("reading.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let record = try JSONDecoder().decode(PaperRecord.self, from: Data(contentsOf: url))
        guard record.id == id, !record.isExcerpt else { return nil }
        return record
    }
    func renderGraph() {
        do {
            let graph = try knowledgeStore()
            let active = store.papers.filter { !$0.archived }
            let edges = graph.entries.filter { $0.relation.from.paper == selectedID || $0.relation.to.paper == selectedID }
            let ids = Set(edges.flatMap { [$0.relation.from.paper, $0.relation.to.paper] })
            let sources = try active.filter { ids.contains($0.id) }.map { paper in
                PaperMemory.source(paper, record: try paper.readingID.flatMap(readingRecord), question: "")
            }
            let relations = graph.valid(sources: sources)
            graphView.loadHTMLString(PaperMemoryHTML.graph(selected: selected, papers: active, relations: relations, sources: sources), baseURL: nil)
        } catch {
            graphView.loadHTMLString(ReadingHTML.document("<p>内容关系暂时无法读取。原有卡片和阅读资料仍保留。</p><p>\(ReadingHTML.escape(error.localizedDescription))</p>"), baseURL: nil)
        }
    }
    @objc func newConversation() {
        cancelMemory(); memoryTurns = []; memoryFocus = nil; scopeLabel.stringValue = "全部未归档论文"
        memoryDepth.selectItem(at: 0)
        questionField.stringValue = ""; memoryView.loadHTMLString(PaperMemoryHTML.conversation([]), baseURL: nil)
        tabs.selectTabViewItem(withIdentifier: "memory"); window.makeFirstResponder(questionField)
        statusLabel.stringValue = "新对话 · 可描述印象，也可比较多篇论文"
    }
    @objc func askCurrent() {
        guard let paper = selected else { return }
        newConversation(); memoryFocus = paper.id; scopeLabel.stringValue = "当前论文：\(paper.title)"
        scopeLabel.maximumNumberOfLines = 1; scopeLabel.toolTip = paper.title
    }
    @objc func askMemory() {
        if memoryTask != nil { cancelMemory(); return }
        startMemory(questionField.stringValue, focus: memoryFocus, onlyFocus: memoryFocus != nil)
    }
    @objc func analyzeRelations() {
        guard let paper = selected, memoryTask == nil else { return }
        newConversation()
        let question = "请找出论文库中与《\(paper.title)》相关的论文，比较研究问题、方法或结果。对有双边依据的内容生成关系；不要仅凭共同标签建立关联。"
        questionField.stringValue = question
        startMemory(question, focus: paper.id, onlyFocus: false)
    }
    func memoryBusy(_ value: Bool) {
        questionField.isEnabled = !value; askButton.title = value ? "取消" : (owner?.service.answerTitle ?? "回答")
        memoryDepth.isEnabled = !value
        for item in [localSearchButton, copyMemoryButton, exportMemoryButton] { item?.isEnabled = !value }
        relationButton.isEnabled = !value && selected != nil; askCurrentButton.isEnabled = !value && selected != nil
    }
    func cancelMemory() {
        memoryRequest = UUID(); memoryTask?.cancel(); memoryTask = nil; memoryBusy(false)
        statusLabel.stringValue = "已取消 · 现有回答与关系均保留"
    }
    func startMemory(_ raw: String, focus: UUID?, onlyFocus: Bool) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 2000 else { statusLabel.stringValue = "请输入 1–2000 字符的问题。"; return }
        // Flush pending edits in the existing reading window before gathering its notes.
        owner?.reader?.flushNotes()
        let papers = store.papers, history = memoryTurns
        let id = UUID(); memoryRequest = id; memoryBusy(true); tabs.selectTabViewItem(withIdentifier: "memory")
        statusLabel.stringValue = "正在准备论文库…"
        let selectedService = owner?.service ?? .deepseek
        let depth = MemoryDepth(rawValue: memoryDepth.indexOfSelectedItem) ?? .compact
        memoryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let service = PaperMemoryService { messages in
                    guard let owner = self.owner else { throw AssistantFailure(message: "请重新打开论文索引。") }
                    return try await owner.modelResponse(messages: messages, maxTokens: depth.outputLimit, jsonOutput: true, using: selectedService)
                }
                let turn = try await service.ask(question: question, papers: papers, turns: history, focus: focus, onlyFocus: onlyFocus, depth: depth, record: self.readingRecord) { text in
                    if self.memoryRequest == id { self.statusLabel.stringValue = text }
                }
                guard !Task.isCancelled, self.memoryRequest == id else { return }
                let activeIDs = Set(self.store.papers.filter { !$0.archived }.map(\.id))
                guard turn.sources.allSatisfy({ activeIDs.contains($0.id) }) else { throw AssistantFailure(message: "本轮涉及的论文已归档，请重新提问。") }
                self.memoryTurns.append(turn); self.questionField.stringValue = ""
                self.memoryView.loadHTMLString(PaperMemoryHTML.conversation(self.memoryTurns), baseURL: nil)
                do {
                    if !turn.answer.relations.isEmpty { try self.knowledgeStore().merge(turn, activeIDs: activeIDs) }
                    let size = turn.sources.reduce(0) { $0 + $1.excerpts.reduce(0) { $0 + $1.text.count } }
                    self.statusLabel.stringValue = turn.sources.isEmpty ? "未找到匹配 · 未调用模型" : "\(selectedService.title) · \(depth.title) · \(turn.sources.count) 篇 · \(size) 字符摘录 · 可继续追问"
                } catch { self.statusLabel.stringValue = "已回答；关系未能保存：\(error.localizedDescription)" }
                self.renderGraph()
            } catch {
                if self.memoryRequest == id {
                    self.statusLabel.stringValue = Task.isCancelled ? "已取消" : error.localizedDescription
                }
            }
            if self.memoryRequest == id { self.memoryTask = nil; self.memoryBusy(false) }
        }
    }

    func preparedMemoryContext() throws -> MemoryContext {
        owner?.reader?.flushNotes()
        let question = questionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = question.isEmpty ? (memoryTurns.last?.question ?? "") : question
        let depth = MemoryDepth(rawValue: memoryDepth.indexOfSelectedItem) ?? .compact
        return try PaperMemoryService.prepare(question: raw, papers: store.papers, turns: memoryTurns, focus: memoryFocus, onlyFocus: memoryFocus != nil, depth: depth, record: readingRecord)
    }
    @objc func findMemoryLocally() {
        let question = questionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 2000 else { statusLabel.stringValue = "先输入要找的论文线索。"; return }
        let depth = MemoryDepth(rawValue: memoryDepth.indexOfSelectedItem) ?? .compact
        let papers = memoryFocus.map { id in store.papers.filter { $0.id == id && !$0.archived } } ?? MemoryLocalSearch.retrieve(question: question, papers: store.papers, turns: memoryTurns, focus: nil, limit: depth.paperLimit)
        let body = "<h2>本地检索</h2><p class='meta'>按标题、摘要、主题和常用中英文词匹配，未调用模型。\(papers.isEmpty ? "未找到匹配，可换关键词或补充卡片。" : "候选论文如下，可继续提问或复制材料。")</p>" + papers.map { "<h3>\(PaperMemoryHTML.paperLink($0.id, title: $0.title))</h3><p>\(ReadingHTML.escape($0.brief))</p>" }.joined()
        memoryView.loadHTMLString(ReadingHTML.document(body), baseURL: nil)
        statusLabel.stringValue = "本地找到 \(papers.count) 篇候选 · 0 次模型调用"
    }
    @objc func copyMemoryContext() {
        do {
            let context = try preparedMemoryContext()
            guard !context.sources.isEmpty else { statusLabel.stringValue = "未找到相关论文，没有复制。请补充关键词。"; return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(context.markdown(), forType: .string)
            statusLabel.stringValue = "已复制 \(context.sources.count) 篇、\(context.excerptCharacters) 字符摘录 · 可粘贴到其他工具 · 未调用模型"
        } catch { statusLabel.stringValue = error.localizedDescription }
    }
    @objc func exportMemoryContext() {
        do {
            let context = try preparedMemoryContext()
            guard !context.sources.isEmpty else { statusLabel.stringValue = "未找到相关论文，请补充关键词。"; return }
            let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]; panel.nameFieldStringValue = "论文提问材料.md"
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let self, let url = panel.url else { return }
                do {
                    try context.markdown().write(to: url, atomically: true, encoding: .utf8)
                    self.statusLabel.stringValue = "已导出提问材料 · 可交给 Claude Code、Codex 或 ChatGPT · 未调用模型"
                } catch { self.statusLabel.stringValue = error.localizedDescription }
            }
        } catch { statusLabel.stringValue = error.localizedDescription }
    }
}
