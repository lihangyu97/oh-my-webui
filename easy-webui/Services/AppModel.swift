import Foundation
import Combine

/// 状态中枢：命令列表 + 每命令的运行实例
@MainActor
final class AppModel: ObservableObject {

    @Published var commands: [CommandApp] = []
    @Published var selectedID: UUID?
    @Published var presentEditor = false
    @Published var editorTarget: CommandApp?   // nil = 新增；非 nil = 编辑

    private var runtimes: [UUID: WebCLIRunner] = [:]
    private let storeURL: URL
    private var didAutoStart = false

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storeURL = dir.appendingPathComponent("easy-webui/commands.json")
        commands = Self.load(from: storeURL)
        if selectedID == nil {
            selectedID = commands.first?.id
        }
    }

    var selectedCommand: CommandApp? {
        commands.first { $0.id == selectedID }
    }

    // MARK: - 运行时

    func runtime(for command: CommandApp) -> WebCLIRunner {
        if let r = runtimes[command.id] { return r }
        let r = WebCLIRunner()
        runtimes[command.id] = r
        return r
    }

    func toggle(_ command: CommandApp) {
        let r = runtime(for: command)
        if r.isRunning {
            r.stop()
        } else {
            r.start(command: command.command, workingDirectory: command.workingDirectory)
        }
    }

    func autoStartOnce() {
        guard !didAutoStart else { return }
        didAutoStart = true
        for cmd in commands where cmd.autoStart {
            runtime(for: cmd).start(command: cmd.command, workingDirectory: cmd.workingDirectory)
        }
    }

    func stopAll() {
        for r in runtimes.values {
            r.stop()
        }
    }

    // MARK: - CRUD

    func beginAdd() {
        editorTarget = nil
        presentEditor = true
    }

    func beginEdit(_ command: CommandApp) {
        editorTarget = command
        presentEditor = true
    }

    func add(_ command: CommandApp) {
        commands.append(command)
        selectedID = command.id
        save()
    }

    func update(_ command: CommandApp) {
        if let i = commands.firstIndex(where: { $0.id == command.id }) {
            commands[i] = command
            save()
        }
    }

    func remove(_ command: CommandApp) {
        runtimes[command.id]?.stop()
        runtimes.removeValue(forKey: command.id)
        commands.removeAll { $0.id == command.id }
        if selectedID == command.id {
            selectedID = commands.first?.id
        }
        save()
    }

    // MARK: - 持久化

    func save() {
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(commands) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [CommandApp] {
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([CommandApp].self, from: data),
           !list.isEmpty {
            return list
        }
        // 首次运行：内置一条 dsh web 预设
        return [
            CommandApp(name: "dsh web", command: "npx @deepseek-ai/dsh web")
        ]
    }
}
