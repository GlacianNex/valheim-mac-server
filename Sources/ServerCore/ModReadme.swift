import Foundation

/// Normalize README block syntax for the native text view. Never execute HTML or fetch embedded resources.
public enum ModReadme {
    public static func displayText(_ input:String) -> String {
        var text = input
        func replace(_ pattern:String,_ template:String) {
            guard let regex = try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive]) else { return }
            text = regex.stringByReplacingMatches(in:text,range:NSRange(text.startIndex...,in:text),withTemplate:template)
        }
        for (entity,value) in [("&lt;","<"),("&gt;",">"),("&quot;","\""),("&#39;","'"),("&nbsp;"," "),("&amp;","&")] { text = text.replacingOccurrences(of:entity,with:value) }
        replace(#"(?s)<!--.*?-->"#, "")
        replace(#"(?s)<(script|style)\b[^>]*>.*?</\1\s*>"#, "")
        replace(#"<a\b[^>]*href=["'](https?://[^"']+)["'][^>]*>(.*?)</a>"#, "[$2]($1)")
        replace(#"</?(?:p|div|h[1-6]|tr|table|details|summary)\b[^>]*>|<br\s*/?>"#, "\n")
        replace(#"<li\b[^>]*>"#, "\n• ")
        replace(#"</t[dh]\s*>"#, " — ")
        replace(#"<[^>]+>"#, "")
        replace(#"!\[([^\]]*)\]\([^\n]*?\)"#, "$1")
        // Mixed HTML/Markdown often leaves whitespace just inside emphasis delimiters.
        replace(#"\*\*\s*([^*]+?)\s*\*\*"#, "**$1**")
        replace(#"(?m)^\s*>\s?"#, "")
        let lines = text.components(separatedBy:"\n")
        var result:[String] = [], i = 0, fenced = false
        func cells(_ line:String) -> [String] {
            var value = line.trimmingCharacters(in:.whitespaces)
            if value.hasPrefix("|") { value.removeFirst() }; if value.hasSuffix("|") { value.removeLast() }
            return value.components(separatedBy:"|").map { $0.trimmingCharacters(in:.whitespaces) }
        }
        func separator(_ line:String) -> Bool {
            let columns = cells(line)
            return !columns.isEmpty && columns.allSatisfy { $0.range(of:#"^:?-{3,}:?$"#,options:.regularExpression) != nil }
        }
        while i < lines.count {
            let line = lines[i], trimmed = line.trimmingCharacters(in:.whitespaces)
            if trimmed.hasPrefix("```") { fenced.toggle(); result.append(""); i += 1; continue }
            if fenced { result.append(line); i += 1; continue }
            if i + 1 < lines.count, line.contains("|"), separator(lines[i+1]) {
                let headers = cells(line); i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in:.whitespaces).isEmpty {
                    let values = cells(lines[i])
                    result.append(values.enumerated().map { offset,value in offset < headers.count ? "**" + headers[offset] + ":** " + value : value }.joined(separator:"\n"))
                    result.append(""); i += 1
                }
                continue
            }
            if separator(trimmed) { result.append("") }
            else if trimmed.hasPrefix("#") {
                let heading = String(trimmed.drop(while:{$0 == "#" || $0 == " "}))
                result.append(heading.hasPrefix("**") && heading.hasSuffix("**") ? heading : "**" + heading + "**")
            }
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { result.append("• " + trimmed.dropFirst(2)) }
            else if !trimmed.isEmpty || result.last?.isEmpty == false { result.append(trimmed.isEmpty ? "" : line) }
            i += 1
        }
        return result.joined(separator:"\n")
    }
}
