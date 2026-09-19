import Foundation
import Darwin

public struct RconEndpoint: Codable { public let port: Int; public let pid: Int32; public let version: String }
public final class RconClient {
    private let fd: Int32
    public init(port: Int, password: String) throws {
        guard (1...65535).contains(port) else { throw MonitorError("Invalid management port.") }
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MonitorError("Cannot create the management connection.") }
        var timeout = timeval(tv_sec: 5, tv_usec: 0), noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        do {
            let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard result == 0 else { throw MonitorError("Server management is not ready.") }
            _ = try exchange(password, type: 3)
        } catch { close(fd); throw error }
    }
    deinit { close(fd) }
    public func send(_ text: String) throws -> String { try exchange(text, type: 2) }
    private func exchange(_ text: String, type: Int32) throws -> String {
        let message = Data(text.utf8)
        guard message.count <= 4086 else { throw MonitorError("Management message is too long.") }
        var data = Data()
        for value in [Int32(message.count + 10), 1, type] { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(message); data.append(contentsOf: [0,0])
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < data.count {
                let n = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), data.count-offset, 0)
                guard n > 0 else { throw MonitorError("Management connection failed.") }; offset += n
            }
        }
        func number(_ bytes: Data) -> Int32 { Int32(bitPattern: bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }) }
        let size = Int(number(try read(4)))
        guard (10...1_048_576).contains(size) else { throw MonitorError("Invalid management response.") }
        let response = try read(size)
        guard number(response.prefix(4)) == 1, number(Data(response.dropFirst(4).prefix(4))) == (type == 3 ? 2 : 0), response.suffix(2) == Data([0,0]),
              let result = String(data: response.dropFirst(8).dropLast(2), encoding: .utf8) else { throw MonitorError("Management authentication or response failed.") }
        guard !result.hasPrefix("ERROR:") else { throw MonitorError(result) }
        return result
    }
    private func read(_ count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            var offset = 0
            while offset < count {
                let n = recv(fd, raw.baseAddress!.advanced(by: offset), count-offset, 0)
                guard n > 0 else { throw MonitorError("Server management did not respond.") }; offset += n
            }
        }
        return data
    }
}
