import Foundation
import SwiftUI

extension AppModel {

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
