import Cocoa

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
        questionField.isEnabled = !value; askButton.title = value ? "取消" : "发送"
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
        let model = owner?.model ?? "deepseek-flash"
        memoryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let savedKey = try await Task.detached(priority: .userInitiated) { try KeyStore.read() }.value
                try Task.checkCancellation()
                guard let key = savedKey, !key.isEmpty else { throw AssistantFailure(message: "请先在 DeepSeek 设置中连接 API Key。") }
                let service = PaperMemoryService { messages in try await DeepSeekClient().reading(messages: messages, key: key, model: model, maxTokens: 10000, jsonOutput: true) }
                let turn = try await service.ask(question: question, papers: papers, turns: history, focus: focus, onlyFocus: onlyFocus, record: self.readingRecord) { text in
                    if self.memoryRequest == id { self.statusLabel.stringValue = text }
                }
                guard !Task.isCancelled, self.memoryRequest == id else { return }
                let activeIDs = Set(self.store.papers.filter { !$0.archived }.map(\.id))
                guard turn.sources.allSatisfy({ activeIDs.contains($0.id) }) else { throw AssistantFailure(message: "本轮涉及的论文已归档，请重新提问。") }
                self.memoryTurns.append(turn); self.questionField.stringValue = ""
                self.memoryView.loadHTMLString(PaperMemoryHTML.conversation(self.memoryTurns), baseURL: nil)
                do {
                    if !turn.answer.relations.isEmpty { try self.knowledgeStore().merge(turn, activeIDs: activeIDs) }
                    self.statusLabel.stringValue = "已回答 · 可继续追问，点击论文名称查看卡片"
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
}
