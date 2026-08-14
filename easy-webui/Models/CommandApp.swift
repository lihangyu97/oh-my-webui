import Foundation

/// 一条可管理的启动命令（持久化为 JSON）
struct CommandApp: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var workingDirectory: String?
    var environment: [String: String] = [:]
    var autoStart = false
    var restartOnExit = false
}
