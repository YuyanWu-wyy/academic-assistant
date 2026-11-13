import Foundation

struct IndexedPaper: Codable, Identifiable {
    var id = UUID()
    var readingID: UUID?
    var title: String
    var sourceURL: String?
    var tags: [String] = []
    var brief = ""
    var manuallyEdited = false
    var archived = false
    var addedAt = Date()
    var lastReadAt = Date()
}

enum PaperIndexText {
    // These are keyword aliases, not inferred scientific relationships.
    static let topics: [(String, [String])] = [
        ("触觉感知", ["tactile", "haptic", "触觉"]),
        ("力感知", ["force sensing", "force perception", "force sensor", "force estimation", "力感知", "力传感", "力估计"]),
        ("传感器", ["sensor", "sensors", "sensing", "传感器", "传感"]),
        ("计算机视觉", ["vision", "visual", "camera", "视觉", "相机"]),
        ("机器人", ["robot", "robots", "robotic", "robotics", "机器人"]),
        ("软体机器人", ["soft robot", "soft robotics", "软体机器人"]),
        ("具身智能", ["embodied", "physical ai", "具身智能", "物理智能"]),
        ("机器学习", ["machine learning", "机器学习"]),
        ("深度学习", ["deep learning", "neural network", "neural networks", "深度学习", "神经网络"]),
        ("注意力机制", ["attention", "transformer", "transformers", "注意力"]),
        ("大语言模型", ["language model", "llm", "llms", "语言模型"]),
        ("强化学习", ["reinforcement learning", "强化学习"]),
        ("扩散模型", ["diffusion model", "diffusion models", "扩散模型"]),
        ("迁移与泛化", ["transfer learning", "domain adaptation", "generalization", "迁移学习", "领域适应", "泛化"]),
        ("自监督学习", ["self-supervised", "self supervised", "自监督"]),
        ("多模态", ["multimodal", "multi-modal", "多模态"]),
        ("运动与控制", ["locomotion", "motion control", "manipulation", "运动控制", "操纵", "步态"]),
        ("振动分析", ["vibration", "vibrations", "modal analysis", "振动", "模态分析"]),
        ("声学", ["acoustic", "acoustics", "sound", "声学", "声音"]),
        ("结构监测", ["structural health", "damage detection", "结构健康", "损伤识别"]),
        ("逆问题", ["inverse problem", "inverse problems", "逆问题", "反演"]),
        ("物理建模", ["physics-informed", "physics informed", "finite element", "物理建模", "有限元"]),
        ("优化", ["optimization", "optimisation", "优化"]),
        ("不确定性", ["uncertainty", "bayesian", "不确定性", "贝叶斯"]),
        ("生物力学", ["biomechanics", "biomechanical", "生物力学"]),
        ("医学成像", ["medical imaging", "mri", "医学成像"]),
        ("可穿戴设备", ["wearable", "wearables", "可穿戴"]),
        ("重量估计", ["weight estimation", "weight sensing", "重量估计", "体重估计"]),
        ("接触建模", ["contact mechanics", "contact modeling", "接触力学", "接触建模"]),
        ("综述", ["survey", "review", "综述"])
    ]
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func titleKey(_ text: String) -> String {
        folded(text).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    static func contains(_ text: String, term: String) -> Bool {
        if term.unicodeScalars.allSatisfy({ $0.isASCII }) {
            let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: term) + "(?![a-z0-9])"
            return text.range(of: pattern, options: .regularExpression) != nil
        }
        return text.contains(term)
    }
    static func tags(title: String, brief: String) -> [String] {
        let text = folded(title + "\n" + brief)
        return Array(topics.filter { $0.1.contains { contains(text, term: $0) } }.map(\.0).prefix(8))
    }
    static func cleanTags(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return Array(raw.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }
            .filter { !$0.isEmpty && seen.insert(folded($0)).inserted }.prefix(16))
    }
    static func brief(from summary: String) -> String {
        var result: [String] = []
        for raw in summary.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("## 2") || line.hasPrefix("## 3") { break }
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(">"), !line.hasPrefix("|"), line != "---" else { continue }
            let plain = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            result.append(plain)
            if result.joined(separator: " ").count >= 400 { break }
        }
        return String(result.joined(separator: " ").prefix(600))
    }
    static func validURL(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https", "file"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              url.isFileURL || !(url.host ?? "").isEmpty else { return nil }
        return url.absoluteString
    }
    static func matches(_ paper: IndexedPaper, query: String) -> Bool {
        let aliases = topics.filter { paper.tags.contains($0.0) }.flatMap(\.1).joined(separator: " ")
        let text = folded(([paper.title, paper.brief, paper.sourceURL ?? "", aliases] + paper.tags).joined(separator: "\n"))
        return folded(query).split(whereSeparator: { $0.isWhitespace }).allSatisfy { text.contains($0) }
    }
    static func sharedTags(_ a: IndexedPaper, _ b: IndexedPaper) -> [String] {
        let other = Set(b.tags.map(folded))
        return a.tags.filter { other.contains(folded($0)) }
    }
    static func related(to paper: IndexedPaper, in papers: [IndexedPaper]) -> [IndexedPaper] {
        papers.filter { $0.id != paper.id && !$0.archived && !sharedTags(paper, $0).isEmpty }.sorted {
            let left = sharedTags(paper, $0).count, right = sharedTags(paper, $1).count
            return left == right ? $0.lastReadAt > $1.lastReadAt : left > right
        }
    }
}

final class PaperIndexStore {
    let root: URL
    var fileURL: URL { root.appendingPathComponent("index.json") }
    private(set) var papers: [IndexedPaper] = []

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/学术助手/PaperIndex")) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: fileURL.path) {
            papers = try JSONDecoder().decode([IndexedPaper].self, from: Data(contentsOf: fileURL))
        } else { papers = [] }
    }
    func save(_ updated: [IndexedPaper]) throws {
        let data = try JSONEncoder().encode(updated)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        papers = updated
    }
    func match(title: String, sourceURL: String?, readingID: UUID?) -> Int? {
        if let readingID, let index = papers.firstIndex(where: { $0.readingID == readingID }) { return index }
        if let source = PaperDownload.canonical(sourceURL), let index = papers.firstIndex(where: { PaperDownload.canonical($0.sourceURL) == source }) { return index }
        let title = PaperIndexText.titleKey(title)
        guard title.count >= 12 else { return nil }
        return papers.firstIndex { PaperIndexText.titleKey($0.title) == title && ($0.sourceURL == nil || sourceURL == nil) }
    }
    @discardableResult
    func collect(title: String, sourceURL: String?, readingID: UUID? = nil, summary: String = "", readAt: Date = Date()) throws -> IndexedPaper {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        guard !title.isEmpty else { throw AssistantFailure(message: "请输入论文名称。") }
        let url = PaperIndexText.validURL(sourceURL)
        let index = match(title: title, sourceURL: url, readingID: readingID)
        var paper = index.map { papers[$0] } ?? IndexedPaper(title: title, sourceURL: url)
        if !paper.manuallyEdited {
            paper.title = title
            if let url { paper.sourceURL = url }
            let brief = PaperIndexText.brief(from: summary)
            if !brief.isEmpty { paper.brief = brief }
            paper.tags = PaperIndexText.tags(title: paper.title, brief: paper.brief)
        }
        if let readingID { paper.readingID = readingID }
        paper.lastReadAt = index == nil ? readAt : max(paper.lastReadAt, readAt)
        var updated = papers
        if let index { updated[index] = paper } else { updated.append(paper) }
        try save(updated)
        return paper
    }
    func synchronize(_ records: [PaperRecord]) throws {
        // Only card metadata is copied. Full text, PDF bytes, notes and conversations stay out.
        for record in records where !record.isExcerpt {
            _ = try collect(title: record.title, sourceURL: record.sourceURL, readingID: record.id, summary: record.summary, readAt: record.updatedAt)
        }
    }
    func update(_ paper: IndexedPaper) throws {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { throw AssistantFailure(message: "未找到这张论文卡片，请刷新后重试。") }
        var paper = paper
        paper.title = String(paper.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        guard !paper.title.isEmpty else { throw AssistantFailure(message: "论文名称不能为空。") }
        if let raw = paper.sourceURL, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let url = PaperIndexText.validURL(raw) else { throw AssistantFailure(message: "请填写完整的 http/https 论文链接，或留空。") }
            paper.sourceURL = url
        } else { paper.sourceURL = nil }
        paper.tags = PaperIndexText.cleanTags(paper.tags)
        paper.brief = String(paper.brief.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        var updated = papers; updated[index] = paper; try save(updated)
    }
    func search(_ query: String, archived: Bool = false) -> [IndexedPaper] {
        papers.filter { $0.archived == archived && PaperIndexText.matches($0, query: query) }.sorted { $0.lastReadAt > $1.lastReadAt }
    }
    func markdown() -> String {
        "# 我的论文索引\n\n仅包含论文卡片，不包含 PDF 或全文。主题关联表示共享标签，不代表引用关系。\n\n" + search("").map {
            "## \($0.title.replacingOccurrences(of: "\n", with: " "))\n\n" + ($0.sourceURL.map { "原文：\($0)\n\n" } ?? "") + "主题：\($0.tags.joined(separator: "、"))\n\n\($0.brief)\n"
        }.joined(separator: "\n")
    }
}

enum PaperIndexHTML {
    static func graph(_ selected: IndexedPaper?, papers: [IndexedPaper]) -> String {
        guard let paper = selected else { return ReadingHTML.document("<h1>找回读过的论文</h1><p>选择左侧一篇论文，查看通过共同主题连接的其他论文。</p><p>通过助手导入的论文会自动收录；也可以只收藏标题和链接，不下载 PDF。</p>") }
        let related = PaperIndexText.related(to: paper, in: papers)
        let visible = Array(related.prefix(8))
        let topics = paper.tags.filter { topic in visible.contains { $0.tags.map(PaperIndexText.folded).contains(PaperIndexText.folded(topic)) } }
        let heading = "<p class='meta'>主题关联 · \(related.count) 篇相关论文\(related.count > 8 ? "（图中显示前 8 篇）" : "")</p><h1>\(ReadingHTML.escape(paper.title))</h1><p>连线表示共享主题标签，不表示引用、支持或因果关系。</p>"
        guard !visible.isEmpty else { return ReadingHTML.document(heading + "<p class='empty'>还没有共享标签的论文。可编辑卡片标签，或继续收藏论文。</p>") }
        let height = max(topics.count, visible.count) * 74 + 30
        var svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 740 \(height)' role='img' aria-label='共同主题连接相关论文'><style>text{font-family:-apple-system,sans-serif;fill:#17443d}rect{fill:#e6f3ed;stroke:#79b4a4}.paper{fill:#f9fcfa;stroke:#c1d8ce}line{stroke:#a8c9bd;stroke-width:1.4}</style>"
        for (i, topic) in topics.enumerated() {
            for (j, other) in visible.enumerated() where other.tags.map(PaperIndexText.folded).contains(PaperIndexText.folded(topic)) {
                svg += "<line x1='180' y1='\(i * 74 + 42)' x2='265' y2='\(j * 74 + 42)'/>"
            }
        }
        for (i, topic) in topics.enumerated() {
            svg += "<rect x='4' y='\(i * 74 + 20)' width='176' height='44' rx='20'/><text x='92' y='\(i * 74 + 48)' text-anchor='middle' font-size='16'>\(ReadingHTML.escape(String(topic.prefix(12))))</text>"
        }
        for (i, other) in visible.enumerated() {
            let title = ReadingHTML.escape(other.title).replacingOccurrences(of: "'", with: "&#39;")
            let short = ReadingHTML.escape(String(other.title.prefix(32)) + (other.title.count > 32 ? "…" : ""))
            svg += "<a href='paper-index://\(other.id.uuidString)' aria-label='\(title)'><title>\(title)</title><rect class='paper' x='265' y='\(i * 74 + 10)' width='466' height='64' rx='10'/><text x='279' y='\(i * 74 + 36)' font-size='15'>\(short)</text><text x='279' y='\(i * 74 + 59)' font-size='12'>\(ReadingHTML.escape(PaperIndexText.sharedTags(paper, other).joined(separator: " · ")))</text></a>"
        }
        return ReadingHTML.document(heading + svg + "</svg><p class='meta'>点击论文节点查看对应卡片。主题来自本机关键词提取或你的编辑，可随时修正。</p>")
    }
}
