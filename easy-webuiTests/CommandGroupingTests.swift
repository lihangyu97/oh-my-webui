import XCTest

/// 有序分组：组顺序 = 首次出现顺序，同组命令在数组内保持相对顺序
@MainActor
final class CommandGroupingTests: XCTestCase {

    private func cmd(_ name: String, _ wd: String?) -> CommandApp {
        CommandApp(name: name, command: "echo \(name)", workingDirectory: wd)
    }

    func testOrderedGrouping() {
        let model = AppModel()
        model.commands = [
            cmd("a", "/p/a"), cmd("b", "/p/a"),
            cmd("c", "/p/b"),
            cmd("d", nil),
            cmd("e", "/p/a"),
        ]
        let sections = model.commandSections

        XCTAssertEqual(sections.map(\.path), ["/p/a", "/p/b", nil])
        XCTAssertEqual(sections[0].commands.map(\.name), ["a", "b", "e"])
        XCTAssertEqual(sections[1].commands.map(\.name), ["c"])
        XCTAssertEqual(sections[2].commands.map(\.name), ["d"])
    }

    func testGroupOrderFollowsFirstAppearance() {
        let model = AppModel()
        model.commands = [cmd("x", "/q/b"), cmd("y", "/q/a")]
        XCTAssertEqual(model.commandSections.map(\.path), ["/q/b", "/q/a"])
    }

    func testEmptyCommandsYieldNoSections() {
        let model = AppModel()
        model.commands = []
        XCTAssertTrue(model.commandSections.isEmpty)
    }
}
