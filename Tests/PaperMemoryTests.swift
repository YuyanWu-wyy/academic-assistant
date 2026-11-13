import Foundation

@main struct PaperMemoryTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }; print("PASS: \(message)")
    }
    static func expectFailure(_ message: String, _ run: () throws -> Void) {
        do { try run(); fatalError(message) } catch { print("PASS: \(message)") }
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = try PaperIndexStore(root: root)
        var a = try index.collect(title: "Optical tactile force estimation", sourceURL: "https://example.org/a?private_link_token=PRIVATE_LINK")
        var b = try index.collect(title: "Capacitive contact force estimation", sourceURL: nil)
        var ra = PaperRecord(title: a.title, pages: [PaperPage(number: 1, text: "PRIVATE_PDF_TEXT")])
        ra.summary = "该方法从相机图像回归接触力，使用已知负载进行标定。\n\n实验比较了不同载荷下的误差，但没有开展跨设备验证。"
        ra.notes = "个人笔记：需核对独立测试集的设置。"
        ra.turns = [ReadingTurn(question: "PRIVATE_READING_QUESTION", passage: "PRIVATE_PASSAGE", answer: "PRIVATE_ANSWER")]
        var rb = PaperRecord(title: b.title, pages: [])
        rb.summary = "该方法从电容变化估计接触力，使用已知负载进行标定。"
        a.readingID = ra.id; b.readingID = rb.id; a.brief = "使用相机估计接触力"; b.brief = "使用电容估计接触力"
        try index.update(a); try index.update(b)
        let sa = PaperMemory.source(a, record: ra, question: "如何标定"), sb = PaperMemory.source(b, record: rb, question: "如何标定")
        let payload = try PaperMemory.json(sa)
        check(payload.contains("个人笔记") && payload.contains("相机图像"), "Selected sources reuse existing overview and notes")
        check(!payload.contains("PRIVATE_"), "Source payload excludes PDF text, reading conversations and private link URLs")
        let ca = MemoryCitation(paper: a.id, excerpt: "E2", quote: "该方法从相机图像回归接触力，使用已知负载进行标定。")
        let cb = MemoryCitation(paper: b.id, excerpt: "E2", quote: "该方法从电容变化估计接触力，使用已知负载进行标定。")
        let relation = MemoryRelation(kind: .differentMethod, reason: "都估计接触力，但观测信号分别为图像和电容。", from: ca, to: cb)
        let answer = MemoryAnswer(claims: [MemoryClaim(text: "两篇论文都估计接触力，但采用不同信号。", citations: [ca, cb])], relations: [relation], limitation: "依据已有导读，具体实验条件需核对原文。")
        let raw = try PaperMemory.json(answer)
        let verified = try PaperMemory.validated(raw, sources: [sa, sb])
        check(verified.relations.count == 1, "Cross-paper answer and typed relation retain evidence from both papers")
        let fenced = try PaperMemory.validated("```json\n" + raw + "\n```", sources: [sa, sb])
        check(fenced.claims.count == 1, "JSON code fences are accepted without extracting arbitrary embedded text")
        let fabricated = MemoryCitation(paper: a.id, excerpt: "E2", quote: "结果达到百分之百准确率，这是捏造的。");
        let grounded = try PaperMemory.validated(PaperMemory.json(MemoryAnswer(claims: [MemoryClaim(text: "需核对解释", citations: [fabricated])], relations: [], limitation: "")), sources: [sa])
        check(grounded.claims[0].citations[0].quote == ca.quote, "Model-authored quotes cannot replace the actual local evidence excerpt")
        let idOnly = "{\"claims\":[{\"text\":\"用相机估计接触力\",\"citations\":[{\"paper\":\"\(a.id.uuidString)\",\"excerpt\":\"E2\"}]}],\"relations\":[],\"limitation\":\"\"}"
        let bound = try PaperMemory.validated(idOnly, sources: [sa])
        check(bound.claims[0].citations[0].quote == ca.quote, "Identifier-only model citations bind directly to local source paragraphs")
        expectFailure("Unknown paper identifiers are rejected") { _ = try PaperMemory.validated(PaperMemory.json(MemoryAnswer(claims: [MemoryClaim(text: "bad", citations: [MemoryCitation(paper: UUID(), excerpt: "E2", quote: ca.quote)])], relations: [], limitation: "")), sources: [sa]) }
        expectFailure("Wrong excerpt identifiers are rejected") { _ = try PaperMemory.validated(PaperMemory.json(MemoryAnswer(claims: [MemoryClaim(text: "bad", citations: [MemoryCitation(paper: a.id, excerpt: "E99", quote: ca.quote)])], relations: [], limitation: "")), sources: [sa]) }
        expectFailure("Uncited claims cannot be presented as grounded answers") { _ = try PaperMemory.validated(PaperMemory.json(MemoryAnswer(claims: [MemoryClaim(text: "bad", citations: [])], relations: [], limitation: "")), sources: [sa]) }
        expectFailure("Self-relations are rejected") { _ = try PaperMemory.validated(PaperMemory.json(MemoryAnswer(claims: [], relations: [MemoryRelation(kind: .sameProblem, reason: "bad", from: ca, to: ca)], limitation: "none")), sources: [sa]) }
        let noEvidence = try PaperMemory.validated(PaperMemory.json(MemoryAnswer(claims: [], relations: [], limitation: "没有足够的实验资料。")), sources: [sa])
        check(noEvidence.claims.isEmpty, "Insufficient evidence can produce an explicit unanswered result")

        var many = (0..<3000).map { IndexedPaper(title: "Unrelated astronomy catalog \($0)", sourceURL: nil) }; many.append(a)
        var calls = 0, sourceLoads = 0
        let service = PaperMemoryService { messages in
            calls += 1
            let input = messages[1]["content"] as! String
            check(input.contains("相机图像") && !input.contains("PRIVATE_") && !input.contains("Unrelated astronomy"), "One answer request contains only locally selected evidence, not the full catalog or PDFs")
            return try PaperMemory.json(MemoryAnswer(claims: [MemoryClaim(text: "你可能在找这篇视觉触觉论文。", citations: [ca])], relations: [], limitation: "依据卡片和已有导读。"))
        }
        let first = try await service.ask(question: "之前哪篇用摄像头测接触力？", papers: many, turns: [], record: { id in sourceLoads += 1; return id == ra.id ? ra : nil })
        check(calls == 1 && sourceLoads == 1 && first.sources.map(\.id) == [a.id], "A 3001-paper library retrieves an old paper locally with one model call and one record load")
        var generic = IndexedPaper(title: "Attention Is All You Need", sourceURL: nil); generic.brief = "这篇论文提出 Transformer，使用注意力机制。"
        let precise = MemoryLocalSearch.retrieve(question: "之前哪篇论文用相机估计接触力？", papers: [a,generic], turns: [], focus: nil, limit: 3)
        check(precise.map(\.id) == [a.id], "Generic Chinese paper phrases do not upload unrelated candidates")
        check(MemoryLocalSearch.terms("VibFM的方法").contains("vibfm"), "Mixed Chinese and English queries preserve named model terms")
        var followupSawHistory = false
        let followup = PaperMemoryService { messages in
            let input = messages[1]["content"] as! String
            followupSawHistory = input.contains("之前哪篇用摄像头") && input.contains("相机和电容的方法有什么区别")
            return raw
        }
        let second = try await followup.ask(question: "相机和电容的方法有什么区别？", papers: [a,b], turns: [first], record: { id in id == ra.id ? ra : rb })
        check(followupSawHistory && second.sources.count == 2, "Comparison gathers locally matched papers and includes bounded conversation context")
        let pronouns = MemoryLocalSearch.retrieve(question: "它们各有什么局限？", papers: [a,b], turns: [second], focus: nil, limit: 3)
        check(Set(pronouns.map(\.id)) == Set([a.id,b.id]), "Pronoun follow-ups retain the preceding papers without a model retrieval call")
        var focusedCalls = 0
        let focused = PaperMemoryService { _ in
            focusedCalls += 1
            return try PaperMemory.json(MemoryAnswer(claims: [MemoryClaim(text: "使用已知负载标定。", citations: [ca])], relations: [], limitation: ""))
        }
        let focusedTurn = try await focused.ask(question: "如何标定？", papers: [a,b], turns: [], focus: a.id, onlyFocus: true, record: { _ in ra })
        check(focusedCalls == 1 && focusedTurn.sources.map(\.id) == [a.id], "Single-paper questions cannot silently pull in another paper")
        var malformedCalls = 0
        let malformed = PaperMemoryService { _ in malformedCalls += 1; return "{\"claims\":[],\"relations\":[]}" }
        do { _ = try await malformed.ask(question: "相机", papers: [a], turns: [], record: { _ in ra }); fatalError("Accepted malformed answer") } catch { }
        check(malformedCalls == 1, "Malformed responses never trigger an automatic additional paid request")
        var archived = b; archived.archived = true
        let noNetwork = PaperMemoryService { _ in fatalError("Unexpected model call") }
        let archivedTurn = try await noNetwork.ask(question: "如何标定", papers: [a,archived], turns: [], focus: b.id, onlyFocus: true, record: { _ in fatalError("Loaded archived record") })
        check(archivedTurn.sources.isEmpty, "Archived papers cannot be reintroduced through a focused question")
        let missing = try await noNetwork.ask(question: "天文学", papers: [a,b], turns: [], record: { _ in fatalError("Loaded non-selected paper") })
        check(missing.sources.isEmpty && !missing.answer.limitation.isEmpty, "No-match searches need zero model calls and load no unrelated records")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await noNetwork.ask(question: "相机", papers: [a], turns: [], record: { _ in fatalError("Loaded material after cancellation") })
        }
        do { _ = try await cancelled.value; fatalError("Ignored cancellation") } catch is CancellationError { print("PASS: Cancelled work cannot load records or call the model") }
        let cancelsAfterAnswer = PaperMemoryService { _ in withUnsafeCurrentTask { $0?.cancel() }; return idOnly }
        let stopped = Task { try await cancelsAfterAnswer.ask(question: "相机", papers: [a], turns: [], record: { _ in ra }) }
        do { _ = try await stopped.value; fatalError("Accepted cancelled answer") } catch is CancellationError { print("PASS: Cancellation during a model request prevents accepting the result") }

        var huge = ra; huge.summary = String(repeating: "相机测接触力，标定误差。\n\n", count: 2500)
        var pool = (0..<20).map { IndexedPaper(title: "Camera force calibration \($0)", sourceURL: nil) }
        for i in pool.indices { pool[i].readingID = huge.id }
        let compact = try PaperMemoryService.prepare(question: "相机接触力", papers: pool, turns: Array(repeating: second, count: 100), record: { _ in huge })
        let detailed = try PaperMemoryService.prepare(question: "相机接触力", papers: pool, turns: [], depth: .detailed, record: { _ in huge })
        check(compact.sources.count == 3 && compact.excerptCharacters <= 6000 && compact.history.count <= 2000, "Default context caps papers, excerpts and conversation independently of library size")
        check(detailed.sources.count == 6 && detailed.excerptCharacters <= 30000 && detailed.excerptCharacters > compact.excerptCharacters, "Only explicit detailed mode expands the evidence budget")
        let export = try PaperMemoryService.prepare(question: "相机标定", papers: [a,b], turns: [], focus: a.id, onlyFocus: true, record: { _ in ra }).markdown()
        check(export.contains("[P1:E2]") && export.contains(a.title) && export.contains("相机图像") && !export.contains("PRIVATE_") && !export.contains(b.title), "Portable Markdown keeps the question, selected evidence and source labels without private links, PDFs or unrelated papers")
        check(PaperMemory.source(a, record: huge, question: "相机", characterLimit: 2000).fingerprint == PaperMemory.source(a, record: huge, question: "相机", characterLimit: 5000).fingerprint, "Budget changes do not invalidate unchanged stored relationships")

        let graph = try PaperRelationStore(root: root)
        try graph.merge(second, activeIDs: Set([a.id,b.id])); try graph.merge(second, activeIDs: Set([a.id,b.id]))
        let restored = try PaperRelationStore(root: root)
        check(restored.entries.count == 1 && restored.valid(sources: [sa,sb]).count == 1, "Typed relations survive restart and repeated answers do not duplicate edges")
        var changed = ra; changed.summary += "修订后的新证据。"
        check(restored.valid(sources: [PaperMemory.source(a, record: changed, question: ""), sb]).isEmpty, "Changed source material invalidates old relations instead of presenting stale evidence")
        check(restored.valid(sources: [sa]).isEmpty, "Archived or missing papers disappear from the displayed content graph")
        let stored = try String(contentsOf: restored.fileURL, encoding: .utf8)
        check(!stored.contains("PRIVATE_") && !stored.contains("个人笔记"), "Graph stores short relationship evidence, not full reading records or unrelated notes")
        let permissions = try FileManager.default.attributesOfItem(atPath: restored.fileURL.path)[.posixPermissions] as! NSNumber
        check(permissions.intValue == 0o600, "Saved relations remain private to the local user")
        let html = PaperMemoryHTML.conversation([second])
        check(html.contains("paper-index://\(a.id.uuidString)") && html.contains("查看依据"), "Answers expose clickable paper sources and inspectable evidence")
        let graphHTML = PaperMemoryHTML.graph(selected: a, papers: [a,b], relations: [relation], sources: [sa,sb])
        check(graphHTML.contains("方法差异") && graphHTML.contains(ca.quote) && graphHTML.contains(cb.quote), "Content graph labels relation types and shows both evidence quotes")
        let hostile = MemoryTurn(question: "<script>bad</script>", answer: MemoryAnswer(claims: [MemoryClaim(text: "<img src=x onerror=bad>", citations: [ca])], relations: [], limitation: ""), sources: [sa])
        let inert = PaperMemoryHTML.conversation([hostile])
        check(!inert.contains("<script>") && !inert.contains("<img src=x"), "Model and user text render as inert content")
        var long = ra; long.summary = (0..<70).map { "段落\($0)：" + String(repeating: "导读内容", count: 350) }.joined(separator: "\n\n")
        long.summary += "\n\n稀有验证条件：独立测试负载以及跨设备标定。"
        let short = PaperMemory.source(a, record: long, question: "独立测试负载跨设备标定")
        check(short.shortened && short.excerpts.reduce(0, { $0 + $1.text.count }) <= 20_000 && short.excerpts.contains { $0.text.contains("稀有验证条件") }, "Long material is bounded and relevant late evidence is retained with an explicit excerpt flag")
        try Data("broken".utf8).write(to: graph.fileURL)
        expectFailure("Corrupted relation files are reported without silently replacing them") { _ = try PaperRelationStore(root: root) }
    }
}
