import Foundation

enum PaperMemoryHTML {
    static func paperLink(_ id: UUID, title: String) -> String {
        "<a href='paper-index://\(id.uuidString)'>\(ReadingHTML.escape(title))</a>"
    }
    static func evidence(_ citation: MemoryCitation, sources: [MemorySource]) -> String {
        guard let source = sources.first(where: { $0.id == citation.paper }) else { return "" }
        let label = source.excerpts.first { $0.id == citation.excerpt }?.label ?? "保存的依据"
        return "<p>\(paperLink(source.id, title: source.title)) · \(ReadingHTML.escape(label))</p><blockquote>\(ReadingHTML.escape(citation.quote))</blockquote>"
    }
    static func conversation(_ turns: [MemoryTurn]) -> String {
        guard !turns.isEmpty else {
            return ReadingHTML.document("<h2>问读过的论文</h2><p>之前哪篇论文用视觉估计接触力？</p><p>它是怎么做实验的？这些方法有什么区别？</p><p class='meta'>从卡片找论文，再查已有导读和笔记。回答附来源；资料不足时会说明。</p>")
        }
        let body = turns.reversed().map { turn in
            var html = "<section class='turn'><p class='question'>\(ReadingHTML.escape(turn.question))</p>"
            for claim in turn.answer.claims {
                // PDF page numbers in a multi-paper answer are not unambiguous navigation targets.
                html += ReadingHTML.markdown(claim.text).replacingOccurrences(of: #"<a href="paper-page://\d+">([^<]*)</a>"#, with: "$1", options: .regularExpression)
                var seen = Set<UUID>()
                html += "<p class='meta'>" + claim.citations.filter { seen.insert($0.paper).inserted }.map { citation in
                    let title = turn.sources.first { $0.id == citation.paper }?.title ?? "论文"
                    return paperLink(citation.paper, title: title)
                }.joined(separator: " · ") + "</p>"
                html += "<details><summary>查看依据</summary>" + claim.citations.map { evidence($0, sources: turn.sources) }.joined() + "</details>"
            }
            if !turn.answer.limitation.isEmpty { html += "<blockquote>\(ReadingHTML.escape(turn.answer.limitation))</blockquote>" }
            if turn.sources.contains(where: \.shortened) { html += "<p class='meta'>较长的导读或笔记按问题选取了相关段落，未提供全文。</p>" }
            if !turn.answer.relations.isEmpty { html += "<p class='meta'>本轮整理了 \(turn.answer.relations.count) 条内容关联，可在“关联图谱”查看。</p>" }
            return html + "</section>"
        }.joined()
        return ReadingHTML.document(body)
    }
    static func graph(selected: IndexedPaper?, papers: [IndexedPaper], relations: [MemoryRelation], sources: [MemorySource]) -> String {
        guard let selected else { return PaperIndexHTML.graph(nil, papers: papers) }
        let connected = relations.filter { $0.from.paper == selected.id || $0.to.paper == selected.id }
        guard !connected.isEmpty else { return PaperIndexHTML.graph(selected, papers: papers) }
        let shown = Array(connected.prefix(12)), height = shown.count * 100 + 30
        let center = height / 2
        var body = "<p class='meta'>\(connected.count) 条内容关联 · AI 依据已有资料归纳，需核对原文</p>"
        body += "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 900 \(height)' aria-label='论文内容关联图'><style>text{font-family:-apple-system,sans-serif;fill:#17443d}.node{fill:#edf7f1;stroke:#91bbaa}line{stroke:#9dbeb2;stroke-width:2}</style>"
        for (i, relation) in shown.enumerated() {
            let other = relation.from.paper == selected.id ? relation.to.paper : relation.from.paper
            let title = papers.first { $0.id == other }?.title ?? "论文"
            let y = i * 100 + 60
            body += "<line x1='260' y1='\(center)' x2='510' y2='\(y)'/><rect fill='#fbfcfa' x='310' y='\(y - 12)' width='180' height='28' rx='12'/><text x='400' y='\(y + 7)' font-size='16' text-anchor='middle'>\(relation.kind.title)</text>"
            body += "<a href='paper-index://\(other.uuidString)'><title>\(ReadingHTML.escape(title))</title><rect class='node' x='510' y='\(y - 34)' width='380' height='68' rx='12'/><text x='526' y='\(y - 5)' font-size='16'>\(ReadingHTML.escape(String(title.prefix(38))))</text><text x='526' y='\(y + 19)' font-size='16'>\(ReadingHTML.escape(String(title.dropFirst(38).prefix(38))))\(title.count > 76 ? "…" : "")</text></a>"
        }
        body += "<rect class='node' x='4' y='\(center - 45)' width='256' height='90' rx='14'/><text x='18' y='\(center - 13)' font-size='16'>\(ReadingHTML.escape(String(selected.title.prefix(25))))</text><text x='18' y='\(center + 11)' font-size='16'>\(ReadingHTML.escape(String(selected.title.dropFirst(25).prefix(25))))</text><text x='18' y='\(center + 32)' font-size='13'>当前论文</text></svg>"
        for relation in shown {
            body += "<details><summary>\(relation.kind.title) · 查看依据</summary><p>\(ReadingHTML.escape(relation.reason))</p>" + evidence(relation.from, sources: sources) + evidence(relation.to, sources: sources) + "</details>"
        }
        return ReadingHTML.document(body)
    }
}
