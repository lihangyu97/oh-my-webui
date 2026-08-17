import Foundation
import Combine
import SwiftUI

/// 状态中枢：命令列表 + 每命令的运行实例。
/// 按职责拆成多个 extension 文件：
/// - AppModel+Runtime.swift：进程启停
/// - AppModel+Commands.swift：命令 CRUD 与分组
/// - AppModel+Persistence.swift：JSON 持久化
@MainActor
final class AppModel: ObservableObject {

    @Published var commands: [CommandApp] = []
    @Published var selectedID: UUID?
    @Published var presentEditor = false
    @Published var editorTarget: CommandApp?   // nil = 新增；非 nil = 编辑

    /// 运行实例按命令 id 索引，与列表顺序无关（顺序只影响显示）
    var runtimes: [UUID: WebCLIRunner] = [:]
    let storeURL: URL
    var didAutoStart = false

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
}
