import XCTest
import FolderServeCore
@testable import FolderServe

final class RemovalPromptTests: XCTestCase {
    private func entry(name: String? = nil, rules: Int = 0) -> ServerEntry {
        var e = ServerEntry(id: UUID(), bookmark: Data(), folderPath: "/Users/me/Projects/shop-dist", preferredPort: nil,
                            options: ServeOptions(), autoStart: true)
        e.customName = name
        e.options.proxyRules = (0..<rules).map { ProxyRule(prefix: "/api\($0)", target: "http://localhost:300\($0)") }
        return e
    }

    func testTitleUsesTheShownNameNotTheFolderName() {
        XCTAssertEqual(RemovalPrompt.title(for: entry()), "Remove “shop-dist” from FolderServe?")
        XCTAssertEqual(RemovalPrompt.title(for: entry(name: "Shop (Angular)")), "Remove “Shop (Angular)” from FolderServe?")
    }

    func testStoppedFolderMessageHasNoServerSentence() {
        let m = RemovalPrompt.message(for: entry(), status: .stopped)
        XCTAssertEqual(m, "It will disappear from this list and its settings will be forgotten. The files in the folder are not deleted.")
    }

    func testRunningFolderSaysItsServerWillStop() {
        let m = RemovalPrompt.message(for: entry(), status: .running(port: 8080))
        XCTAssertTrue(m.hasPrefix("Its server on port 8080 will stop."), m)
    }

    func testSearchingFolderIsMentioned() {
        let search = PortSearch(busy: [], landed: nil, began: Date(), duration: 1.5)
        XCTAssertTrue(RemovalPrompt.message(for: entry(), status: .finding(search)).hasPrefix("Its server is starting and will be stopped."))
    }

    func testCustomNameAndProxyRulesAreListedAsWhatIsForgotten() {
        XCTAssertTrue(RemovalPrompt.message(for: entry(name: "Shop", rules: 1), status: .stopped).contains("(custom name, 1 proxy rule)"))
        XCTAssertTrue(RemovalPrompt.message(for: entry(rules: 3), status: .stopped).contains("(3 proxy rules)"))
    }

    func testAlwaysReassuresThatFilesAreNotDeleted() {
        for status: ServerStatus in [.stopped, .running(port: 1), .folderMissing, .error("x")] {
            XCTAssertTrue(RemovalPrompt.message(for: entry(), status: status).hasSuffix("The files in the folder are not deleted."))
        }
    }
}
