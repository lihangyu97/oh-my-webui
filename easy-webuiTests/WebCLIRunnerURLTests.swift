import XCTest

/// URL 提取纯函数（WebCLIRunner.firstURL）
final class WebCLIRunnerURLTests: XCTestCase {

    func testExtractsHTTPURL() {
        XCTAssertEqual(
            WebCLIRunner.firstURL(in: "dsh web: http://127.0.0.1:3080"),
            URL(string: "http://127.0.0.1:3080")
        )
    }

    func testExtractsHTTPSWithTrailingPunctuation() {
        XCTAssertEqual(
            WebCLIRunner.firstURL(in: "Server ready at https://example.com/app, enjoy!"),
            URL(string: "https://example.com/app")
        )
    }

    func testIgnoresNonHTTP() {
        XCTAssertNil(WebCLIRunner.firstURL(in: "ftp://example.com and mailto:a@b.c"))
    }

    func testFirstURLWins() {
        XCTAssertEqual(
            WebCLIRunner.firstURL(in: "a https://first.com b https://second.com"),
            URL(string: "https://first.com")
        )
    }

    func testURLWithANSIAdjacent() {
        XCTAssertEqual(
            WebCLIRunner.firstURL(in: "\u{1B}[32mhttp://127.0.0.1:3080\u{1B}[0m"),
            URL(string: "http://127.0.0.1:3080")
        )
    }
}
