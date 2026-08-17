import Foundation
import Combine
import SwiftUI
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
        // 注意：不再清理该命令的网页数据（WKWebsiteDataStore）。
        // 实测 WKWebsiteDataStore.remove(forIdentifier:) 在 WebKit 未初始化时调用必崩
        // （崩溃在 WebKit 内部 RunLoop 的 os_unfair_lock，见 removeDataStoreWithIdentifierImpl），
        // 且无法从 App 侧判断 WebKit 是否已初始化。数据残留无害，接受。
    }

    /// 拖拽排序（List.onMove 回调）：重排数组并持久化。
    /// 数组顺序即持久化顺序，运行实例按 UUID 索引，与顺序无关，重排不影响任何进程。
    func move(from source: IndexSet, to destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
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
        // 首次运行：默认空列表，全部由用户手动添加
        return []
    }

    // MARK: - 分组

    /// 有序分组（严格按 workingDirectory 完整路径精确匹配）。
    /// 组顺序 = 该组第一条命令在数组中的位置，组内顺序 = 数组内相对顺序，
    /// 因此无需额外字段，数组顺序承载全部顺序语义，拖拽重排直接持久化。
    var commandSections: [CommandSection] {
        var sections: [CommandSection] = []
        var indexByKey: [String: Int] = [:]
        for cmd in commands {
            let key = cmd.workingDirectory ?? ""
            if let i = indexByKey[key] {
                sections[i].commands.append(cmd)
            } else {
                indexByKey[key] = sections.count
                sections.append(CommandSection(path: cmd.workingDirectory, commands: [cmd]))
            }
        }
        return sections
    }
}

/// 一个命令分组（展示层派生，不持久化）。
/// 注意：不能命名为 CommandGroup——会遮蔽 SwiftUI 的菜单命令组 API CommandGroup。
/// path 为 nil 表示未设置工作目录——运行时默认在 home 目录（~）执行。
struct CommandSection: Identifiable {
    let path: String?          // 完整路径（分组键）；nil = 未设置
    var commands: [CommandApp]

    var id: String { path ?? "home" }

    /// 组名：目录最后两级文件夹名（/a/b/c/d → "c/d"）；根目录显示 "/"；未设置显示 "home"
    var title: String {
        guard let path else { return "home" }
        // 顺带容忍尾斜杠（旧数据可能手输过 /a/b/c/）
        let p = path.hasSuffix("/") && path != "/" ? String(path.dropLast()) : path
        let ns = p as NSString
        let last = ns.lastPathComponent
        guard !last.isEmpty else { return "/" }   // 根目录
        let parentLast = (ns.deletingLastPathComponent as NSString).lastPathComponent
        guard !parentLast.isEmpty else { return last }   // 单级路径 /a → a
        return "\(parentLast)/\(last)"
    }

    /// tooltip：完整路径；未设置时为 home 目录完整路径
    var tooltip: String {
        path ?? FileManager.default.homeDirectoryForCurrentUser.path
    }
}
