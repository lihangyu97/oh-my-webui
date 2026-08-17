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
    private var stopRequested = false
    private let maxLogLines = 100

    /// 预编译正则：static let 全局一份，避免每个 runner 重复编译
    nonisolated private static let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s\x{1B}\]]+"#)

    /// 输出解析器：切行/去 ANSI 在后台串行队列完成，主线程只接收完整行。
    /// 两个 FileHandle（stdout/stderr）共用同一队列，缓冲与切行天然串行，无数据竞争。
    private lazy var parser = OutputParser { [weak self] lines in
        // parser 保证回调已发生在主线程
        MainActor.assumeIsolated {
            self?.commitLines(lines)
        }
    }

    init() {}

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
            // 外层显式弱捕获（同 startReading：Swift 6.2 嵌套闭包捕获会传导到外层）
            guard let self else { return }
            Task { @MainActor in
                // 只处理自己的进程：快速重启时，旧进程的退出回调不能误清新进程
                guard self.process === proc else { return }
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
        // 捕获 process 而非 self：即使 runner 因删除命令被释放，进程清理仍会执行，
        // 也不会用强引用延长 runner 的生命周期
        let proc = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if proc.isRunning { proc.terminate() }   // SIGTERM
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }   // 兜底强杀
        }
    }

    // MARK: - 输出处理

    private func startReading(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] h in
            // Swift 6.2 起嵌套闭包对 self 的捕获会传导到外层：外层不写 weak 的话，
            // readabilityHandler（被 FileHandle 持有）会强持有 self，内层 weak 形同虚设，
            // 且形成 FileHandle→闭包→self 的强环直到 EOF 才断开。这里外层显式弱捕获。
            guard let self else {
                h.readabilityHandler = nil
                return
            }
            let data = h.availableData
            if data.isEmpty {              // EOF
                h.readabilityHandler = nil
                return
            }
            // hop 到主线程访问 parser（属性隔离），parser 内部再投到后台队列做切行/去 ANSI
            Task { @MainActor in
                self.parser.append(data)
            }
        }
    }

    /// 主线程：接收解析好的完整行，更新日志与 URL
    private func commitLines(_ lines: [String]) {
        for line in lines {
            appendLog(line)
            scanURL(in: line)
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
        if let u = Self.firstURL(in: text) {
            self.url = u
        }
    }

    /// 从一行输出中提取第一个 http(s) URL（去掉行尾常见标点）。
    /// 纯函数，便于单测。
    nonisolated static func firstURL(in text: String) -> URL? {
        let nsRange = NSRange(text.startIndex..., in: text)
        var found: URL?
        Self.urlRegex.enumerateMatches(in: text, range: nsRange) { match, _, stop in
            guard let match, let r = Range(match.range(at: 0), in: text) else { return }
            let raw = String(text[r])
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "),.;:!?'\""))
            if let u = URL(string: trimmed), u.scheme == "http" || u.scheme == "https" {
                found = u
                stop.pointee = true
            }
        }
        return found
    }
}

/// 输出字节流解析器：把原始数据切成"去 ANSI 的完整行"。
/// 声明为 nonisolated 脱离默认 MainActor 隔离，在自建串行队列上运行，
/// 高频日志解析不占用主线程；两路输出共用同一队列，无数据竞争。
nonisolated final class OutputParser {

    private let queue = DispatchQueue(label: "lhy.easy-webui.output", qos: .userInitiated)
    private var buffer = Data()            // 跨块拼接，防止 URL 被拦腰切断
    private let ansiRegex = try! NSRegularExpression(pattern: #"\e\[[0-9;?]*[A-Za-z]"#)
    /// 解析出完整行后的回调；实现保证已在主线程调用
    private let onLines: @Sendable ([String]) -> Void

    init(onLines: @escaping @Sendable ([String]) -> Void) {
        self.onLines = onLines
    }

    /// 追加原始数据（任意线程调用，内部串行处理）
    func append(_ data: Data) {
        queue.async { [self] in
            consume(data)
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        let text = String(decoding: buffer, as: UTF8.self)

        var complete: [String]
        if text.hasSuffix("\n") {
            complete = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { Self.stripANSI($0, regex: ansiRegex) }
            buffer.removeAll(keepingCapacity: true)
        } else {
            let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
            complete = parts.dropLast().map { Self.stripANSI($0, regex: ansiRegex) }
            buffer = Data((parts.last ?? "").utf8)   // 不完整的尾行留给下次
        }
        // "a\nb\n" 按 \n 切分会带出末尾空串（"b" 与 ""），日志无意义，过滤掉
        complete.removeAll { $0.isEmpty }

        guard !complete.isEmpty else { return }
        let lines = complete
        DispatchQueue.main.async {
            self.onLines(lines)
        }
    }

    private static func stripANSI(_ s: Substring, regex: NSRegularExpression) -> String {
        let str = String(s)
        return regex.stringByReplacingMatches(
            in: str,
            range: NSRange(str.startIndex..., in: str),
            withTemplate: ""
        )
    }
}
