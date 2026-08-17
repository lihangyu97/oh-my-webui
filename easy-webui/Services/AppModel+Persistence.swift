import Foundation
import os

extension AppModel {

    private static let log = Logger(subsystem: "lhy.easy-webui", category: "persistence")

    func save() {
        let dir = storeURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(commands)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            Self.log.error("保存命令列表失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    static func load(from url: URL) -> [CommandApp] {
        do {
            let data = try Data(contentsOf: url)
            let list = try JSONDecoder().decode([CommandApp].self, from: data)
            if list.isEmpty {
                Self.log.notice("命令列表为空（首次运行或文件为空）")
            }
            return list
        } catch {
            // 首次运行文件不存在是正常情况；损坏/解码失败时记日志，不静默吞掉
            Self.log.error("读取命令列表失败：\(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
