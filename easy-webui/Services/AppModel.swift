import Foundation
import Combine
import WebKit

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
        purgeWebData(for: command.id)
    }

    /// 删除服务时清掉它的持久化网页数据（localStorage/cookie 等）。
    /// 需先释放使用该 store 的 WKWebView：窗口内容此时已切到"服务不存在"，
    /// 但 SwiftUI 释放视图树有短暂延迟，故延后 2 秒再删，失败则忽略（数据残留无害）。
    private func purgeWebData(for id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            WKWebsiteDataStore.remove(forIdentifier: id) { _ in }
        }
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
        // 首次运行：默认空列表，全部由用户手动添加
        return []
    }
}
