import Foundation

/// Surfaces author text for review; does not interpret it as executable instructions.
public struct ModInstallInstructions {
    public let excerpts: [String]
    public let mayNeedExtraSteps: Bool
    public var found: Bool { !excerpts.isEmpty }

    public init(markdown: String) {
        let lines = markdown.components(separatedBy: .newlines)
        var sections: [String] = [], current: [String] = [], level = 0
        func heading(_ line: String) -> (Int, String)? {
            let text = line.trimmingCharacters(in: .whitespaces)
            let depth = text.prefix(while: { $0 == "#" }).count
            guard depth > 0 && depth <= 6 else { return nil }
            return (depth, String(text.dropFirst(depth)).trimmingCharacters(in: .whitespaces))
        }
        func isSetup(_ text: String) -> Bool {
            text.range(of: #"\b(install(?:ation|ing)?|setup|set up|configuration|configuring|manual steps|requirements)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        for line in lines {
            if let (depth, title) = heading(line) {
                if !current.isEmpty && depth <= level { sections.append(current.joined(separator: "\n")); current = [] }
                if current.isEmpty && isSetup(title) { level = depth; current = [line]; continue }
            }
            if !current.isEmpty { current.append(line) }
        }
        if !current.isEmpty { sections.append(current.joined(separator: "\n")) }
        // Also catch short descriptions and bold/plain headings without Markdown # syntax.
        if sections.isEmpty {
            sections = markdown.components(separatedBy: "\n\n").filter {
                isSetup($0) || $0.range(of: #"\b(copy|move|place|extract|rename|edit)\b.{0,100}\b(files?|folders?|directories|directory|plugins?|config|dll|json|cfg)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
        excerpts = sections.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        mayNeedExtraSteps = excerpts.joined(separator: "\n").range(of: #"\b(manual(?:ly)?|configur\w*|edit|rename|replace|copy|move|place|extract)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    public var notice: String {
        if !found { return "No installation section detected. This does not establish that setup is automatic; review the full description or mod website." }
        return mayNeedExtraSteps ? "Possible additional setup steps — review the author's instructions below." : "The author provides installation instructions — review them below."
    }
    public var text: String {
        notice + "\n\nDeclared dependencies are downloaded automatically. Instructions may also cover manual installation, Windows, or player-side setup; they are not automatically executed.\n\n" + excerpts.joined(separator: "\n\n")
    }
}
