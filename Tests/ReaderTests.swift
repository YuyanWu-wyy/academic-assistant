import Foundation
import PDFKit

final class ReaderMock: URLProtocol {
    static var handler: ((URLRequest) -> Data)!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ReaderTests {
    static func check(_ ok: @autoclosure () -> Bool, _ message: String) {
        if !ok() { fatalError(message) }; print("PASS: \(message)")
    }
    static func body(_ r: URLRequest) -> Data {
        if let data = r.httpBody { return data }
        let stream = r.httpBodyStream!; stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
        return data
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try PaperLibrary(root: root)
        let pdf = PDFDocument(url: URL(fileURLWithPath: "build/tests/selection-test.pdf"))!
        pdf.insert(pdf.page(at: 0)!.copy() as! PDFPage, at: 1)
        pdf.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Reading test"]
        let data = pdf.dataRepresentation()!
        var paper = try library.importPDF(data, name: "fallback", sourceURL: "https://example.org/paper.pdf")
        check(paper.pages.count == 2 && paper.characterCount > 80 && paper.text.contains("[PDF p. 2]"), "All PDF pages and physical page labels are retained")
        paper.notes = "我的笔记"; paper.summary = "已有导读 [p. 1]"
        paper.turns = (0..<18).map { ReadingTurn(question: "问题\($0)", passage: "引用\($0)", answer: "答案\($0)") }
        try library.save(paper)
        let duplicate = try library.importPDF(data, name: "same")
        check(duplicate.id == paper.id && duplicate.notes == paper.notes && duplicate.turns.count == 18, "Reimport preserves notes and all conversations")
        let images = try library.images(for: paper)
        check(images.count == 2 && images.allSatisfy { $0.1.prefix(2) == Data([0xff, 0xd8]) }, "Every page is rendered for visual evidence")
        check(matchingPaper(for: String(paper.pages[0].text.prefix(100)), sourceURL: nil, papers: [paper])?.id == paper.id, "Selected text associates with its full paper")
        check(matchingPaper(for: "short", sourceURL: "https://example.org/paper.pdf#page=2", papers: [paper])?.id == paper.id, "Browser page fragments match the same PDF")
        check(matchingPaper(for: "An unrelated paragraph with sufficiently many characters to avoid ambiguity.", sourceURL: "https://other.org/x", papers: [paper]) == nil, "Unrelated selections never inherit a previous paper")
        let excerpt = PaperRecord(title: "Excerpt", pages: [PaperPage(number: 1, text: "some selected words")], isExcerpt: true)
        try library.save(excerpt)
        let records = try library.all(); check(records.count == 2, "Separate reading records survive disk reload")
        let base = URL(string: "https://example.org/article/1")!
        let link = PaperDownload.pdfLink(in: "<META content='/paper.pdf?a=1&amp;b=2' name='citation_pdf_url'>", base: base)
        check(link?.absoluteString == "https://example.org/paper.pdf?a=1&b=2", "Publisher PDF metadata resolves relative links")
        check(PaperDownload.pdfLink(in: "<meta name='citation_pdf_url' content='file:///private/test'>", base: base) == nil, "Web metadata cannot load a local file")
        check(PaperDownload.normalizedURL("https://arxiv.org/abs/1706.03762")?.path == "/pdf/1706.03762", "arXiv article links resolve to PDFs")
        let messages = try PaperPrompts.messages(paper: paper, images: images, question: "继续解释", passage: "选中段落")
        let serial = String(data: try JSONSerialization.data(withJSONObject: messages), encoding: .utf8)!
        check(messages.count == 36 && serial.contains("答案17") && !serial.contains("答案0"), "Current paper and recent 16 complete turns reach the request")
        check(serial.contains("image_url") && serial.contains("选中段落"), "Page images and current selection reach the request")
        let excerptMessages = try PaperPrompts.messages(paper: excerpt, images: [])
        check((excerptMessages[0]["content"] as! String).contains("单独选中的段落，没有完整论文"), "Excerpt-only context is explicitly bounded")
        check(PaperPrompts.citationWarning("证据 [p. 3]", pageCount: 2) != nil && PaperPrompts.citationWarning("证据 [p. 2]", pageCount: 2) == nil, "Out-of-range page citations are flagged")
        check(PaperPrompts.citationWarning("证据 [p. 1–3]", pageCount: 2) != nil && ReadingHTML.inline("证据 [p. 1–2]").contains("paper-page://1"), "Page ranges link to their start and validate both bounds")
        let html = ReadingHTML.markdown("<script>alert(1)</script>\n## 结果\n证据 [p. 2]\n| A | B |\n| --- | --- |\n| 1 | 2 |")
        check(!html.contains("<script>") && html.contains("paper-page://2") && html.contains("<table>"), "Model text is escaped while page links and tables render")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReaderMock.self]
        let client = DeepSeekClient(session: URLSession(configuration: config))
        ReaderMock.handler = { request in
            let payload = try! JSONSerialization.jsonObject(with: body(request)) as! [String: Any]
            check(request.url?.absoluteString == "https://api.deepseek.com/chat/completions" && request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "Reading uses the official endpoint and authorization header")
            check((payload["messages"] as! [Any]).count == messages.count, "Complete reading context reaches the API")
            return Data(#"{"choices":[{"message":{"content":"测试回答 [p. 1]"},"finish_reason":"stop"}]}"#.utf8)
        }
        let answer = try await client.reading(messages: messages, key: "test-key", model: "deepseek-flash")
        check(answer == "测试回答 [p. 1]", "Reading response is decoded")
        ReaderMock.handler = { _ in Data(#"{"choices":[{"message":{"content":"部分回答"},"finish_reason":"length"}]}"#.utf8) }
        do { _ = try await client.reading(messages: messages, key: "test-key", model: "deepseek-flash"); fatalError("Truncation accepted") } catch { print("PASS: Truncated reading is rejected") }
        do { _ = try library.importPDF(Data("not a pdf".utf8), name: "invalid"); fatalError("Invalid PDF accepted") } catch { print("PASS: Invalid PDF rejected") }
        let longPDF = PDFDocument()
        for index in 0..<388 { longPDF.insert(pdf.page(at: 0)!.copy() as! PDFPage, at: index) }
        let longRecord = try library.importPDF(longPDF.dataRepresentation()!, name: "Long monograph")
        check(longRecord.pages.count == 388 && longRecord.pages.last?.number == 388, "388-page PDF imports without dropping pages")
        let selected = try PaperScope.pages("3, 100–102, 388", in: longRecord)
        check(selected.map(\.number) == [3,100,101,102,388], "Chapter ranges preserve physical PDF page numbers")
        do { _ = try PaperScope.pages("387-390", in: longRecord); fatalError("Invalid range accepted") } catch { print("PASS: Out-of-document ranges rejected") }
        do { _ = try library.images(for: longRecord); fatalError("Unbounded long-document images accepted") } catch { print("PASS: Oversized image batch rejected before rendering") }
        let focusedImages = try library.images(for: longRecord, pages: [100,388])
        check(focusedImages.map(\.0) == [100,388], "Images retain original page labels beyond the old import cap")
        let rangeMessages = try PaperPrompts.messages(paper: longRecord, images: focusedImages, pages: selected)
        let rangeSource = (rangeMessages[1]["content"] as! [[String:Any]])[0]["text"] as! String
        check(rangeSource.contains("[PDF p. 388]") && !rangeSource.contains("[PDF p. 1]"), "Chapter request sends only selected pages without renumbering")
        let prosePage = PaperPage(number:1, text:String(repeating:"physical intelligence ", count:70000))
        let largeProse = PaperRecord(title:"Large text", pages:[prosePage])
        let fullMessages = try PaperPrompts.messages(paper: largeProse, images:[])
        check(((fullMessages[1]["content"] as! [[String:Any]])[0]["text"] as! String).contains(prosePage.text), "1.5-million-character text reaches full-document analysis without truncation")
        let exported = readingMarkdown(paper)
        check(exported.contains("我的笔记") && exported.contains("答案0") && exported.contains("答案17"), "Export retains notes and the full conversation, beyond active context")
    }
}
