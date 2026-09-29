import Foundation

public enum JoinAddress {
    public static func ipv4(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            !part.isEmpty && part.count <= 3 && part.utf8.allSatisfy { (48...57).contains($0) }
                && Int(part).map { $0 <= 255 } == true
        }) else { return nil }
        return parts.map { String(Int($0)!) }.joined(separator: ".")
    }
    public static func endpoint(ip: String?, port: Int) -> String? {
        guard let ip, let address = ipv4(ip), (1...65534).contains(port) else { return nil }
        return "\(address):\(port)"
    }
}
