import XCTest

/// CommandSection 的组名/标识/tooltip 边界
final class CommandSectionTests: XCTestCase {

    func testTitleLastTwoComponents() {
        XCTAssertEqual(CommandSection(path: "/a/b/c/d", commands: []).title, "c/d")
        XCTAssertEqual(CommandSection(path: "/Users/me/code/app", commands: []).title, "code/app")
    }

    func testTitleSingleComponent() {
        XCTAssertEqual(CommandSection(path: "/a", commands: []).title, "a")
    }

    func testTitleRoot() {
        XCTAssertEqual(CommandSection(path: "/", commands: []).title, "/")
    }

    func testTitleTrailingSlashTolerated() {
        XCTAssertEqual(CommandSection(path: "/a/b/c/", commands: []).title, "b/c")
        XCTAssertEqual(CommandSection(path: "/a/", commands: []).title, "a")
    }

    func testTitleNilMeansHome() {
        XCTAssertEqual(CommandSection(path: nil, commands: []).title, "home")
    }

    func testID() {
        XCTAssertEqual(CommandSection(path: "/x/y", commands: []).id, "/x/y")
        XCTAssertEqual(CommandSection(path: nil, commands: []).id, "home")
    }

    func testTooltipShowsFullPathOrHome() {
        XCTAssertEqual(CommandSection(path: "/x/y", commands: []).tooltip, "/x/y")
        XCTAssertEqual(
            CommandSection(path: nil, commands: []).tooltip,
            FileManager.default.homeDirectoryForCurrentUser.path
        )
    }
}
