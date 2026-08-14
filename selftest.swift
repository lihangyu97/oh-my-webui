import Foundation
import Combine

/// WebCLIRunner 核心逻辑自测（编译时链接真实的 WebCLIRunner.swift）
@main
struct SelfTest {
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)   // 让 print 立即输出，避免 abort 丢缓冲
        // 1) 带 ANSI 颜色输出的 URL 识别
        let r1 = WebCLIRunner()
        r1.start(command: #"printf '\e[32m dsh web: http://127.0.0.1:3080 \e[0m\n'; sleep 2"#)
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        print("T1 URL(ANSI 行):", r1.url?.absoluteString ?? "NIL")
        assert(r1.url?.absoluteString == "http://127.0.0.1:3080", "T1 失败")

        // 2) URL 被一次 read 切成两半（缓冲拼接）
        let r2 = WebCLIRunner()
        r2.start(command: #"printf 'dsh web: http://127.0.'; sleep 1; printf '0.1:9999\n'; sleep 2"#)
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        print("T2 URL(分块):", r2.url?.absoluteString ?? "NIL")
        assert(r2.url?.absoluteString == "http://127.0.0.1:9999", "T2 失败")

        // 3) 停止：SIGINT → 状态回到 stopped
        let r3 = WebCLIRunner()
        r3.start(command: "sleep 100")
        try? await Task.sleep(nanoseconds: 800_000_000)
        r3.stop()
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        print("T3 停止后状态:", r3.state)
        assert(!r3.isRunning, "T3 失败")

        // 4) 非 0 退出码
        let r4 = WebCLIRunner()
        r4.start(command: "exit 3")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        print("T4 退出码状态:", r4.state)
        assert(r4.state == .exited(code: 3), "T4 失败")

        // 5) GUI 场景模拟：-lic 加载 .zshrc/nvm，最小 PATH 下也能找到 npx
        //    （本测试由外部以 env -i PATH=/usr/bin:/bin:... 运行来模拟 Finder 启动）
        //    找到 → 打印路径且退出码 0(.stopped)；找不到 → 无输出且退出码 1(.exited)
        let r5 = WebCLIRunner()
        r5.start(command: "command -v npx")
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        let log5 = r5.logLines.joined(separator: "\n")
        print("T5 state:", r5.state)
        print("T5 log:", log5)
        assert(r5.state == .stopped && log5.contains("/npx"), "T5 失败")

        // 6) 重启后清空上一次的输出
        let r6 = WebCLIRunner()
        r6.start(command: "echo FIRST_RUN")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        r6.start(command: "echo SECOND_RUN")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let log6 = r6.logLines.joined(separator: "\n")
        print("T6 state:", r6.state)
        print("T6 log:", log6)
        assert(!log6.contains("FIRST_RUN") && log6.contains("SECOND_RUN"), "T6 失败")

        // 7) 未配置工作目录时，默认落在用户主目录（而非 GUI 的 "/"）
        let r7 = WebCLIRunner()
        r7.start(command: "pwd")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let log7 = r7.logLines.joined(separator: "\n")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        print("T7 pwd:", log7)
        print("T7 期望 home:", home)
        assert(log7.contains(home), "T7 失败")

        print("ALL TESTS PASSED ✅")
    }
}
