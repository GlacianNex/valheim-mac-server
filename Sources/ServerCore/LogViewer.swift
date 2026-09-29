import Foundation

public enum LogViewer {
    public static let limit = 256 * 1024
    public static func readable(_ text:String, filter:String = "") -> String {
        let regex = try! NSRegularExpression(pattern:"\\u001B\\[[0-?]*[ -/]*[@-~]")
        let clean = regex.stringByReplacingMatches(in:text,range:NSRange(text.startIndex...,in:text),withTemplate:"")
            .replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").replacingOccurrences(of:"\0",with:"")
        guard !filter.isEmpty else { return clean }
        return clean.components(separatedBy:"\n").filter { $0.localizedCaseInsensitiveContains(filter) }.joined(separator:"\n")
    }
    public static func read(paths:Paths, manager:Bool) -> String {
        if !manager {
            guard let name = try? String(contentsOf:paths.file("latest-log"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines), !name.isEmpty else { return "" }
            return readable(tail(URL(fileURLWithPath:name),bytes:limit))
        }
        let rootLogs = paths.root.appendingPathComponent("logs")
        let label = LoginItems.serviceLabel + (paths.usesLegacyState ? "" : paths.profileID.map { "." + $0 } ?? "")
        let sources:[(String,URL)] = [
            ("Maintenance",rootLogs.appendingPathComponent("maintenance.log")),
            ("Server Manager",paths.logs.appendingPathComponent(label + ".log")),
            ("Server Manager Errors",paths.logs.appendingPathComponent(label + "-error.log")),
            ("Shared Installation",rootLogs.appendingPathComponent("installation.log")),
            ("Manager",rootLogs.appendingPathComponent(LoginItems.monitorLabel + ".log")),
            ("Manager Errors",rootLogs.appendingPathComponent(LoginItems.monitorLabel + "-error.log"))
        ]
        var budget = limit, sections:[String] = []
        for (title,url) in sources where budget > 0 {
            var text = readable(tail(url,bytes:min(budget,limit / sources.count)))
            if title == "Maintenance", let id = paths.profileID {
                text = text.components(separatedBy:"\n").filter { $0.contains("[" + id + "]") || $0.contains("[fleet]") }.joined(separator:"\n")
            }
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { continue }
            budget -= text.utf8.count
            sections.append("── " + title + " ──\n" + text)
        }
        return sections.joined(separator:"\n\n")
    }
}
