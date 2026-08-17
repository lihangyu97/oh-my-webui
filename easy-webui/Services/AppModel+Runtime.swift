import Foundation

extension AppModel {

    /// 取某命令的运行实例（不存在则创建并缓存）
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
}
