import Foundation

enum ReadingHTML {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func inline(_ s: String) -> String {
        var value = escape(s)
        for (pattern, replacement) in [(#"\*\*([^*]+)\*\*"#, "<strong>$1</strong>"), (#"\x60([^\x60]+)\x60"#, "<code>$1</code>"), (#"\[p\.\s*(\d+)(?:\s*[-–—]\s*\d+)?\]"#, #"<a href="paper-page://$1">$0</a>"#)] {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return value
    }
    static func markdown(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var html = "", i = 0
        func cells(_ line: String) -> [String] {
            var bits = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if bits.first == "" { bits.removeFirst() }; if bits.last == "" { bits.removeLast() }
            return bits
        }
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if i + 1 < lines.count, line.contains("|"),
               lines[i + 1].range(of: #"^\s*\|?\s*:?-{3,}"#, options: .regularExpression) != nil {
                html += "<div class='table-wrap'><table><thead><tr>" + cells(line).map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>"
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    html += "<tr>" + cells(lines[i]).map { "<td>\(inline($0))</td>" }.joined() + "</tr>"; i += 1
                }
                html += "</tbody></table></div>"; continue
            }
            if line.hasPrefix("### ") { html += "<h3>\(inline(String(line.dropFirst(4))))</h3>" }
            else if line.hasPrefix("## ") { html += "<h2>\(inline(String(line.dropFirst(3))))</h2>" }
            else if line.hasPrefix("# ") { html += "<h1>\(inline(String(line.dropFirst(2))))</h1>" }
            else if line.hasPrefix("> ") { html += "<blockquote>\(inline(String(line.dropFirst(2))))</blockquote>" }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { html += "<p class='bullet'>• \(inline(String(line.dropFirst(2))))</p>" }
            else if !line.isEmpty { html += "<p>\(inline(line))</p>" }
            i += 1
        }
        return html
    }
    static func document(_ body: String) -> String {
        """
        <!doctype html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:"><style>
        :root{color-scheme:light dark}body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:15px;line-height:1.85;margin:0;padding:24px;color:#203536;background:#fbfcfa;overflow-wrap:anywhere}
        h1{font-size:23px;line-height:1.4}h2{font-size:18px;margin:28px 0 10px;border-top:1px solid #dce7e3;padding-top:18px;color:#126d67}h3{font-size:16px;margin:20px 0 8px}p{margin:9px 0}strong{font-weight:650}a{color:#12786d;text-decoration:none;background:#e1f1eb;border-radius:4px;padding:1px 4px}code{font-family:ui-monospace,monospace;font-size:.9em;background:#edf2f0;padding:2px 4px;border-radius:3px}.bullet{padding-left:13px}.table-wrap{overflow-x:auto}table{border-collapse:collapse;font-size:13px;min-width:100%;margin:14px 0}td,th{border:1px solid #d8e3dd;padding:9px;text-align:left;vertical-align:top;min-width:70px}th{background:#edf5f0;font-weight:600}blockquote{margin:12px 0;padding:12px 16px;background:#f0f4f0;border-left:3px solid #79a69a;color:#50615d}.empty{color:#74857f;padding:20px 0}.turn{margin-bottom:28px;padding-bottom:20px;border-bottom:1px solid #dce7e3}.role{color:#12786d;font-weight:650;font-size:12px;letter-spacing:1px}.question{font-weight:600;font-size:16px}.meta{font-size:12px;color:#74857f}
        @media(prefers-color-scheme:dark){body{color:#e0eae5;background:#202825}h2{color:#8acabb;border-color:#45554f}a{color:#afe6d5;background:#304b42}td,th{border-color:#52635a}th,blockquote,code{background:#303c36}blockquote{color:#c2d0c8}.empty,.meta{color:#a5b8ad}.turn{border-color:#45554f}}
        </style></head><body>\(body)</body></html>
        """
    }
}
