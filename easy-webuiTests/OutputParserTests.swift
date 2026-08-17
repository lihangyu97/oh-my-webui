import XCTest

/// 输出解析：跨块切行、去 ANSI、EOF 收尾
final class OutputParserTests: XCTestCase {

    /// 保持 parser 存活到断言完成（parser 是测试的局部对象，回调可能晚于方法返回）
    private func keepAlive(_ parser: OutputParser) {
        objc_setAssociatedObject(self, "parser", parser, .OBJC_ASSOCIATION_RETAIN)
    }

    func testSplitLinesAndStripANSI() {
        let exp = expectation(description: "lines")
        let parser = OutputParser { lines in
            XCTAssertEqual(lines, ["ab", "c", "plain"])
            exp.fulfill()
        }
        keepAlive(parser)

        // "\u{1B}[31m" = ANSI 红色；末尾换行保证 plain 行完整输出
        parser.append(Data("a\u{1B}[31mb\nc\nplain\u{1B}[0m\n".utf8))
        wait(for: [exp], timeout: 2)
    }

    func testURLNotSplitAcrossChunks() {
        let exp = expectation(description: "lines")
        let parser = OutputParser { lines in
            XCTAssertEqual(lines, ["http://127.0.0.1:3080", "done"])
            exp.fulfill()
        }
        keepAlive(parser)

        // URL 被拦腰切断在两个数据块里，仍应拼成完整行
        parser.append(Data("http://127.0.0.1".utf8))
        parser.append(Data(":3080\ndone\n".utf8))
        wait(for: [exp], timeout: 2)
    }

    func testEmptyChunkProducesNoLines() {
        let exp = expectation(description: "lines")
        exp.isInverted = true
        let parser = OutputParser { _ in
            exp.fulfill()
        }
        keepAlive(parser)

        parser.append(Data())
        wait(for: [exp], timeout: 0.5)
    }

    func testUnterminatedTailKeptForNextChunk() {
        let exp = expectation(description: "lines")
        let parser = OutputParser { lines in
            XCTAssertEqual(lines, ["complete"])
            exp.fulfill()
        }
        keepAlive(parser)

        // 第一块没有换行结尾 → 不产生行；第二块补全后一起输出
        parser.append(Data("complete".utf8))
        parser.append(Data("\n".utf8))
        wait(for: [exp], timeout: 2)
    }
}
