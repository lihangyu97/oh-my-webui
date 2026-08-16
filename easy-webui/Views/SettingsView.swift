import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// 数据存储位置列表里的一行（一个文件或目录）
fileprivate struct DataFileRow: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let url: URL
    var exists: Bool
    var size: Int64

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}

/// 数据文件列表状态（用 ObservableObject 而非 @State，避免宏展开的坑）
fileprivate final class DataFilesModel: ObservableObject {
    @Published var rows: [DataFileRow] = []
}

/// 设置页（App 菜单 → 设置…，⌘,）
///
/// 目前只有一项：指定浏览器（用于详情页链接下方的"指定浏览器打开"按钮）。
/// 未设置时使用系统默认浏览器。
struct SettingsView: View {
    @AppStorage("preferredBrowserPath") private var preferredBrowserPath = ""
    @AppStorage("webWindowStyle") private var webWindowStyle = WebWindowStyle.normal.rawValue

    /// 数据存储位置列表（应用运行时写入本机的文件）
    @StateObject private var filesModel = DataFilesModel()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    /// 常见浏览器（按 bundle id 检测，装了的才会出现在列表里）
    private static let knownBrowsers: [(name: String, bundleID: String)] = [
        ("Safari", "com.apple.Safari"),
        ("Google Chrome", "com.google.Chrome"),
        ("Microsoft Edge", "com.microsoft.edgemac"),
        ("Firefox", "org.mozilla.firefox"),
        ("Arc", "company.thebrowser.Browser"),
        ("Brave", "com.brave.Browser"),
        ("Opera", "com.operasoftware.Opera"),
    ]

    var body: some View {
        Form {
            Picker("指定浏览器", selection: $preferredBrowserPath) {
                Text("系统默认").tag("")
                ForEach(detectedBrowsers, id: \.path) { b in
                    Text(b.name).tag(b.path)
                }
                if let custom = customBrowser {
                    Text(custom.name).tag(custom.path)
                }
            }
            .help("详情页链接下方的“指定浏览器打开”按钮使用的浏览器")

            HStack {
                Button("选择其他浏览器…") { chooseBrowserApp() }
                Spacer()
            }

            Text("未设置时使用系统默认浏览器打开链接；"
                 + "指定后，详情页链接下方会显示“指定浏览器打开”按钮。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Picker("内置浏览器窗口样式", selection: $webWindowStyle) {
                ForEach(WebWindowStyle.allCases) { style in
                    Text(style.label).tag(style.rawValue)
                }
            }
            .help("详情页“在 App 内打开”的内置浏览器窗口外观；切换后已打开的窗口立即生效")

            Text("沉浸式会隐藏标题栏和红绿灯，窗口只能通过 ⌘W 或菜单关闭。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Section {
                if filesModel.rows.isEmpty {
                    Text("统计中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filesModel.rows) { row in
                        DataFileRowView(row: row)
                    }
                }
            } header: {
                HStack {
                    Text("数据存储位置")
                    Spacer()
                    Button {
                        refreshDataRows()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("重新统计")
                }
            } footer: {
                Text("应用写入本机的数据文件；删除服务时，该服务的网页数据目录会自动清除。")
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { refreshDataRows() }
    }

    // MARK: - 数据存储位置

    /// 收集所有运行时数据文件的预期路径
    private func makeRows(fm: FileManager) -> [DataFileRow] {
        let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "lhy.easy-webui"
        var rows: [DataFileRow] = []

        // 1. 服务配置（commands.json）
        let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("easy-webui", isDirectory: true)
        let commandsURL = supportDir.appendingPathComponent("commands.json")
        rows.append(DataFileRow(
            id: "commands", icon: "list.bullet.rectangle",
            title: "服务配置", detail: "已保存的服务列表与启动命令",
            url: commandsURL,
            exists: fm.fileExists(atPath: commandsURL.path), size: 0
        ))

        // 2. 偏好设置（UserDefaults）
        let prefsURL = lib.appendingPathComponent("Preferences/\(bundleID).plist")
        rows.append(DataFileRow(
            id: "prefs", icon: "gearshape",
            title: "偏好设置", detail: "浏览器选择、内置窗口样式等设置",
            url: prefsURL,
            exists: fm.fileExists(atPath: prefsURL.path), size: 0
        ))

        // 3. 网页数据共同父目录（下面每个服务一个子目录：<command.id>）
        let webKitBase = lib.appendingPathComponent("WebKit/\(bundleID)/WebsiteDataStore",
                                                    isDirectory: true)
        rows.append(DataFileRow(
            id: "webkit", icon: "globe",
            title: "网页数据",
            detail: "内置浏览器产生的 localStorage、Cookie 等（每个服务一个子目录）",
            url: webKitBase,
            exists: fm.fileExists(atPath: webKitBase.path), size: 0
        ))
        return rows
    }

    /// 重新统计：先按"是否存在"更新，大小在后台算完再回填
    private func refreshDataRows() {
        let rows = makeRows(fm: FileManager.default)
        filesModel.rows = rows
        Task.detached(priority: .utility) {
            let sized = rows.map { row -> DataFileRow in
                guard row.exists else { return row }
                var r = row
                r.size = Self.sizeOf(r.url, fm: FileManager())
                return r
            }
            await MainActor.run { filesModel.rows = sized }
        }
    }

    /// 文件或目录总大小（递归求和）；非主 actor，供后台任务调用
    nonisolated private static func sizeOf(_ url: URL, fm: FileManager) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(v?.fileSize ?? 0)
        }
        guard let en = fm.enumerator(at: url,
                                     includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        while let u = en.nextObject() as? URL {
            guard let vals = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  vals.isRegularFile == true else { continue }
            total += Int64(vals.fileSize ?? 0)
        }
        return total
    }

    /// 在 Finder 中显示；路径不存在时退回显示最近的已存在父目录
    private static func reveal(_ url: URL) {
        var u = url
        while !FileManager.default.fileExists(atPath: u.path), u.path != "/" {
            u = u.deletingLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting([u])
    }

    /// 设置页里的单行数据文件
    private struct DataFileRowView: View {
        let row: DataFileRow

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: row.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.callout)
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.displayPath)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if row.exists {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(SettingsView.byteFormatter.string(
                            fromByteCount: row.size))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button {
                            SettingsView.reveal(row.url)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .help("在 Finder 中显示")
                    }
                } else {
                    Text("未创建")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 浏览器检测

    /// 本机已安装的常见浏览器（name + 完整路径）
    private var detectedBrowsers: [(name: String, path: String)] {
        Self.knownBrowsers.compactMap { b in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.bundleID)
            else { return nil }
            return (b.name, url.path)
        }
    }

    /// 用户手动选的浏览器（不在常见列表里时展示）
    private var customBrowser: (name: String, path: String)? {
        guard !preferredBrowserPath.isEmpty,
              !detectedBrowsers.contains(where: { $0.path == preferredBrowserPath })
        else { return nil }
        let name = FileManager.default.displayName(atPath: preferredBrowserPath)
        return (name, preferredBrowserPath)
    }

    /// 用 Finder 选任意 .app 作为指定浏览器
    private func chooseBrowserApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.prompt = "选择"
        panel.title = "选择浏览器 App"
        if panel.runModal() == .OK, let url = panel.url {
            preferredBrowserPath = url.path
        }
    }
}
