import Foundation

public struct InstallationProgress {
    public let message: String
    public let percent: Double?

    public static func latest(in log: String) -> InstallationProgress? {
        for line in log.split(whereSeparator: \.isNewline).reversed() {
            let text = String(line), lower = text.lowercased()
            if text.hasPrefix("[Monitor] ") {
                return InstallationProgress(message: String(text.dropFirst(10)), percent: nil)
            }
            if lower.contains("update state") {
                let stage: String
                if lower.contains("downloading") { stage = "Downloading server files" }
                else if lower.contains("verifying") || lower.contains("validating") { stage = "Checking server files" }
                else if lower.contains("preallocating") { stage = "Preparing space for server files" }
                else if lower.contains("committing") || lower.contains("staging") { stage = "Installing server files" }
                else { return InstallationProgress(message: "Preparing server files…", percent: nil) }
                let pattern = #"progress:\s*([0-9]+(?:\.[0-9]+)?)"#
                if let range = text.range(of: pattern, options: .regularExpression),
                   let number = Double(text[range].split(separator: ":").last!.trimmingCharacters(in: .whitespaces)), number.isFinite, (0...100).contains(number) {
                    return InstallationProgress(message: "\(stage) — \(Int(number))%", percent: number)
                }
                return InstallationProgress(message: stage + "…", percent: nil)
            }
            if lower.contains("fully installed") { return InstallationProgress(message: "Finishing installation…", percent: nil) }
            if lower.contains("downloading update") || lower.contains("extracting package") || lower.contains("installing update") {
                return InstallationProgress(message: "Updating Valve’s download tool…", percent: nil)
            }
            if lower.contains("verifying installation") { return InstallationProgress(message: "Checking Valve’s download tool…", percent: nil) }
            if lower.contains("logging in") || lower.contains("waiting for client config") || lower.contains("waiting for user info") {
                return InstallationProgress(message: "Connecting to Valve…", percent: nil)
            }
        }
        return nil
    }
}
