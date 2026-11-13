import Foundation

final class GraphMarkupCheck: NSObject, XMLParserDelegate {
    var unsafe = false
    var labels: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "script" || attributeDict.keys.contains(where: { $0.lowercased().hasPrefix("on") }) { unsafe = true }
        if let label = attributeDict["aria-label"] { labels.append(label) }
    }
}

@main struct PaperIndexTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }; print("PASS: \(message)")
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PaperIndexStore(root: root)
        let date = Date(timeIntervalSince1970: 12345)
        var record = PaperRecord(title: "A tactile sensor for force perception", sourceURL: "https://arxiv.org/abs/1706.03762", pages: [PaperPage(number: 1, text: "PRIVATE_FULL_TEXT_SENTINEL")])
        record.notes = "PRIVATE_NOTES_SENTINEL"; record.turns = [ReadingTurn(question: "PRIVATE_QUESTION", passage: "PRIVATE_PASSAGE", answer: "PRIVATE_ANSWER")]
        record.summary = "> 本轮材料：全文\n\n## 1. 核心想法\n这是一种面向机器人的触觉传感器，用于力感知。\n\n## 2. 主要问题\n这里的后续长文不应进入卡片。"
        record.updatedAt = date
        let excerpt = PaperRecord(title: "An excerpt", pages: [PaperPage(number: 1, text: "excerpt")], isExcerpt: true)
        try store.synchronize([record, excerpt])
        check(store.papers.count == 1, "Only full-paper identities automatically enter the index")
        let first = store.papers[0]
        check(first.lastReadAt == date && first.readingID == record.id, "Initial synchronization preserves reading identity and time")
        check(first.tags.contains("触觉感知") && first.tags.contains("力感知"), "Bilingual keyword tags support remembered research topics")
        check(first.brief.contains("触觉传感器") && !first.brief.contains("后续长文"), "Brief comes from the overview, within its first section")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        check(files == ["index.json"], "Collecting papers creates only a metadata index, no PDF or full-text files")
        let serialized = try String(contentsOf: store.fileURL, encoding: .utf8)
        check(!serialized.contains("PRIVATE_"), "Full text, private notes, questions, passages and answers never enter the index")
        let encoded = try JSONSerialization.jsonObject(with: Data(serialized.utf8)) as! [[String: Any]]
        check(encoded[0]["pages"] == nil && encoded[0]["turns"] == nil && encoded[0]["notes"] == nil, "Index schema cannot serialize the reading document")
        let permissions = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as! NSNumber
        check(permissions.intValue == 0o600, "Index file is private to its owner")
        let duplicate = try store.collect(title: record.title, sourceURL: "https://arxiv.org/pdf/1706.03762#page=3")
        check(duplicate.id == first.id && store.papers.count == 1, "arXiv abstract and PDF page-fragment links deduplicate")
        try store.synchronize([record])
        check(store.papers.count == 1, "Repeated automatic synchronization is idempotent")
        var edited = store.papers[0]
        edited.title = "我的触觉论文"; edited.brief = "自己写的记忆线索"; edited.tags = ["触觉感知", "机器人", "机器人", "  "]; edited.manuallyEdited = true
        try store.update(edited); record.title = "Model-supplied replacement"; record.summary = "Model replacement abstract"
        try store.synchronize([record])
        check(store.papers[0].title == "我的触觉论文" && store.papers[0].brief == "自己写的记忆线索", "Automatic refresh preserves user-edited cards")
        check(store.papers[0].tags == ["触觉感知", "机器人"], "Manual tags are trimmed and deduplicated")
        check(store.search("tactile").count == 1 && store.search("记忆线索").count == 1, "Search covers bilingual topics and brief text")
        check(store.search("tactile nonexistent").isEmpty, "Multiple search terms must all match")
        var other = try store.collect(title: "Another tactile sensor", sourceURL: "https://example.org/second")
        other.tags = ["触觉感知"]; try store.update(other)
        let unrelated = try store.collect(title: "Unrelated astronomy study", sourceURL: "https://example.org/third")
        let related = PaperIndexText.related(to: store.papers[0], in: store.papers)
        check(related.map(\.id) == [other.id] && !related.contains(where: { $0.id == unrelated.id }), "Graph relations require an actual shared tag and exclude self")
        let graph = PaperIndexHTML.graph(store.papers[0], papers: store.papers)
        check(graph.contains("paper-index://\(other.id)") && graph.contains("不表示引用"), "Graph links lead to cards and state their evidence boundary")
        other.title = "<script>bad</script>' onload='bad"; try store.update(other)
        let safeGraph = PaperIndexHTML.graph(store.papers[0], papers: store.papers)
        let svgStart = safeGraph.range(of: "<svg")!, svgEnd = safeGraph.range(of: "</svg>")!
        let parser = XMLParser(data: Data(safeGraph[svgStart.lowerBound..<svgEnd.upperBound].utf8))
        let markup = GraphMarkupCheck(); parser.delegate = markup
        check(parser.parse() && !markup.unsafe && markup.labels.contains(other.title), "Untrusted titles stay inert text and labels in parsed SVG")
        edited = store.papers[0]; edited.archived = true; try store.update(edited); try store.synchronize([record])
        check(store.search("").count == 2 && store.search("", archived: true).count == 1, "Archived cards stay archived across automatic sync")
        check(PaperIndexText.related(to: other, in: store.papers).isEmpty, "Archived cards are omitted from topic relations")
        edited.archived = false; try store.update(edited)
        let reloaded = try PaperIndexStore(root: root)
        check(reloaded.papers.count == 3 && reloaded.search("记忆线索").count == 1, "Cards, edits and restored archives survive restart")
        check(reloaded.markdown().contains("我的触觉论文") && !reloaded.markdown().contains("PRIVATE_"), "Index export contains cards without reading data")
        check(PaperIndexText.validURL("javascript:alert(1)") == nil && PaperIndexText.validURL("https://name:password@example.org") == nil, "Unsafe schemes and embedded URL credentials are rejected")
        var bad = edited; bad.sourceURL = "javascript:alert(1)"
        do { try store.update(bad); fatalError("Accepted unsafe URL") } catch { print("PASS: Invalid card URLs fail without replacing saved data") }
        try Data("damaged".utf8).write(to: store.fileURL)
        do { _ = try PaperIndexStore(root: root); fatalError("Overwrote corrupted index") } catch { print("PASS: Corrupted indexes surface an error instead of being silently overwritten") }
    }
}
