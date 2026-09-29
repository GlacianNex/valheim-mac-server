import XCTest
@testable import ServerCore
final class ModPlayerEvidenceTests: XCTestCase {
    func testExplicitAuthorRequirements() {
        XCTAssertEqual(ModPlayerEvidence.read(readme:"This mod must be installed on both the client and the server.").requirement,.playersRequired)
        XCTAssertEqual(ModPlayerEvidence.read(readme:"All players must install this mod.").requirement,.playersRequired)
        XCTAssertEqual(ModPlayerEvidence.read(readme:"This mod must be installed on client and server.").requirement,.playersRequired)
        XCTAssertEqual(ModPlayerEvidence.read(readme:"Seasons must be installed on the server and every connecting client").requirement,.playersRequired)
        XCTAssertEqual(ModPlayerEvidence.read(readme:"**Server-only**").requirement,.serverOnly)
    }
    func testDoesNotGuessOrMisattributeDependencies() {
        for text in ["Server-side features", "Clients do not need to install this mod", "Dependencies: all clients must install this mod.", "> All players must install this mod.", "Optional: all players must install this mod.", "```\nAll players must install this mod.\n```", "Recommended: install on both client and server"] {
            XCTAssertEqual(ModPlayerEvidence.read(readme:text).requirement,.unknown,text)
        }
        XCTAssertEqual(ModPlayerEvidence.read(declared:.serverOnly,readme:"All players must install this mod.").requirement,.unknown)
    }
    func testDependencyPropagation() {
        XCTAssertEqual(ModPlayerEvidence.includingDependencies(.serverOnly,dependencies:[.playersRequired]),.playersRequired)
        XCTAssertEqual(ModPlayerEvidence.includingDependencies(.serverOnly,dependencies:[.unknown]),.unknown)
        XCTAssertEqual(ModPlayerEvidence.includingDependencies(.serverOnly,dependencies:[.serverOnly]),.serverOnly)
        XCTAssertEqual(ModPlayerEvidence.includingDependencies(.unknown,dependencies:[.playersRequired]),.playersRequired)
    }
}
