import Foundation

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
        if p == "/" { return "/" }   // 根目录
        let ns = p as NSString
        let last = ns.lastPathComponent
        let parentLast = (ns.deletingLastPathComponent as NSString).lastPathComponent
        // 注意：NSString 对根路径的 lastPathComponent 返回 "/" 而非空串，
        // 单级路径（/a → 父级是 "/"）需靠 parentLast == "/" 判断
        if parentLast.isEmpty || parentLast == "/" { return last }   // 单级路径 /a → a
        return "\(parentLast)/\(last)"
    }

    /// tooltip：完整路径；未设置时为 home 目录完整路径
    var tooltip: String {
        path ?? FileManager.default.homeDirectoryForCurrentUser.path
    }
}
