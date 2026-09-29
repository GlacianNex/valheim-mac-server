import XCTest
@testable import ServerCore

final class JoinAddressTests: XCTestCase {
    func testValidatedPublicAddressUsesEachServersPort() {
        XCTAssertEqual(JoinAddress.endpoint(ip: "203.0.113.10\n", port: 2456), "203.0.113.10:2456")
        XCTAssertEqual(JoinAddress.endpoint(ip: "203.0.113.10", port: 2466), "203.0.113.10:2466")
        for ip in ["<html>error</html>", "256.1.2.3", "1.2.3", "1.2.3.4:2456", "1.2.3.-1", "", "::1"] {
            XCTAssertNil(JoinAddress.endpoint(ip: ip, port: 2456))
        }
        XCTAssertNil(JoinAddress.endpoint(ip: nil, port: 2456))
        XCTAssertNil(JoinAddress.endpoint(ip: "203.0.113.10", port: 65535))
    }
}
