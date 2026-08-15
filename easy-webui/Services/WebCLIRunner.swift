import Foundation
import Combine

/// 单条命令的运行实例：Process + Pipe 起停、输出扫描、URL 检测。
/// 零第三方依赖；只关心输出流里的 http(s) 地址。
@MainActor
final class WebCLIRunner: ObservableObject {

    @Published private(set) var state: RunState = .stopped
    @Published private(set) var url: URL?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var pid: Int32?
    @Published private(set) var startedAt: Date?

    private var process: Process?
    private var buffer = Data()            // 跨 read 块拼接，防止 URL 被拦腰切断
    private var stopRequested = false
    private let maxLogLines = 100

    private let urlRegex: NSRegularExpression

    init() {
        urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s\x{1B}\]]+"#)
    }

    var isRunning: Bool {
        switch state {
        case .starting, .running, .stopping: true
        case .stopped, .exited: false
        }
    }

    // MARK: - 启动

    func start(command: String, workingDirectory: String? = nil) {
        guard process == nil else { return }

        // 每次启动清空上一次运行的输出与地址
        logLines.removeAll(keepingCapacity: true)
        url = nil

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -lic = 登录 + 交互式 + 命令：
        // GUI 启动的 App 只继承系统最小 PATH，-lc 不加载 .zshrc（nvm/alias 都在这），
        // 必须 -lic 才会 source .zshrc，npx/node 才找得到。
        p.arguments = ["-lic", command]
        // 工作目录：GUI 启动的 App 默认 cwd 是 "/"（根目录），agent 的相对路径
        // 文件操作会落在根目录。未配置时默认用户主目录，比 "/" 安全得多。
        if let wd = workingDirectory, !wd.isEmpty {
            p.currentDirectoryURL = URL(fileURLWithPath: wd)
        } else {
            p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        var env = ProcessInfo.processInfo.environment
        env["NPM_CONFIG_YES"] = "true"     // npx 首次安装免交互确认
        env["TERM"] = "xterm-256color"
        p.environment = env

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err              // 不少 CLI 把 URL 打在 stderr
        p.standardInput = FileHandle.nullDevice   // 无交互输入，防意外挂起等 EOF

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                // 只处理自己的进程：快速重启时，旧进程的退出回调不能误清新进程
                guard let self, self.process === proc else { return }
                let code = proc.terminationStatus
                self.state = (self.stopRequested || code == 0) ? .stopped : .exited(code: code)
                self.process = nil
                self.pid = nil
                self.startedAt = nil
            }
        }

        startReading(out.fileHandleForReading)
        startReading(err.fileHandleForReading)

        do {
            try p.run()
            process = p
            pid = p.processIdentifier
            startedAt = Date()
            stopRequested = false
            state = .running
            appendLog("$ \(command)")
        } catch {
            state = .exited(code: -1)
            appendLog("启动失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 停止（SIGINT → SIGTERM → SIGKILL 递进）

    func stop() {
        guard let p = process, p.isRunning else { return }
        state = .stopping
        stopRequested = true
        p.interrupt()                      // SIGINT，等价 Ctrl+C，TUI 程序一般优雅退出
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let proc = self.process, proc.isRunning else { return }
            proc.terminate()               // SIGTERM
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard let proc = self.process, proc.isRunning else { return }
            kill(proc.processIdentifier, SIGKILL)   // 兜底强杀
        }
    }

    // MARK: - 输出处理

    private func startReading(_ handle: FileHandle) {
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {              // EOF
                h.readabilityHandler = nil
                return
            }
            Task { @MainActor [weak self] in
                self?.consume(data)
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        let text = String(decoding: buffer, as: UTF8.self)

        var complete: [Substring]
        if text.hasSuffix("\n") {
            complete = text.split(separator: "\n", omittingEmptySubsequences: false)
            buffer.removeAll(keepingCapacity: true)
        } else {
            let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
            complete = parts.dropLast()
            buffer = Data((parts.last ?? "").utf8)   // 不完整的尾行留给下次
        }

        for line in complete {
            let clean = Self.stripANSI(String(line))
            appendLog(clean)
            scanURL(in: clean)
        }
    }

    private func appendLog(_ line: String) {
        guard !line.isEmpty else { return }
        logLines.append(line)
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }
    }

    private func scanURL(in text: String) {
        let nsRange = NSRange(text.startIndex..., in: text)
        urlRegex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match, let r = Range(match.range(at: 0), in: text) else { return }
            let raw = String(text[r])
            // 去掉行尾常见标点
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "),.;:!?'\""))
            if let u = URL(string: trimmed), u.scheme == "http" || u.scheme == "https" {
                self.url = u
            }
        }
    }

    private static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: #"\e\[[0-9;?]*[A-Za-z]"#, with: "", options: .regularExpression)
    }
}
