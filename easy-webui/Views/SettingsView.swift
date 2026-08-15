import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 设置页（App 菜单 → 设置…，⌘,）
///
/// 目前只有一项：指定浏览器（用于详情页链接下方的"指定浏览器打开"按钮）。
/// 未设置时使用系统默认浏览器。
struct SettingsView: View {
    @AppStorage("preferredBrowserPath") private var preferredBrowserPath = ""
    @AppStorage("webWindowStyle") private var webWindowStyle = WebWindowStyle.normal.rawValue

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
        }
        .padding(20)
        .frame(width: 420)
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
