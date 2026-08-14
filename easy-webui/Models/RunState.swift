import Foundation

/// 单条命令的生命周期状态
enum RunState: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case exited(code: Int32)

    var label: String {
        switch self {
        case .stopped: "已停止"
        case .starting: "启动中…"
        case .running: "运行中"
        case .stopping: "停止中…"
        case .exited(let code): "已退出 (code \(code))"
        }
    }
}
