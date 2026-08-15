import SwiftUI
import AppKit

struct CommandDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let command: CommandApp
    @ObservedObject var runner: WebCLIRunner
    @AppStorage("preferredBrowserPath") private var preferredBrowserPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            if let url = runner.url {
                urlSection(url)
            }
            Divider()
            logView
        }
        .padding()
        .toolbar {
            ToolbarItem {
                Button {
                    model.beginEdit(command)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .disabled(runner.isRunning)
                .help("编辑命令（停止后才能修改）")
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(command.name)
                .font(.title2.bold())
            Text(command.command)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let wd = command.workingDirectory, !wd.isEmpty {
                Text(wd)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - 启停 / 状态

    private var controls: some View {
        HStack(spacing: 14) {
            GlassButton(
                runner.isRunning ? "停止" : "启动",
                systemImage: runner.isRunning ? "stop.fill" : "play.fill",
                tint: runner.isRunning ? .red : .green,
                minWidth: 84
            ) {
                model.toggle(command)
            }

            HStack(spacing: 5) {
                StatusDot(state: runner.state, size: 9)
                Text(runner.state.label)
                    .font(.callout)
            }

            if let pid = runner.pid {
                Text("PID \(pid)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            uptime
        }
    }

    private var uptime: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let started = runner.startedAt, runner.isRunning {
                let t = Int(context.date.timeIntervalSince(started))
                Text("已运行 \(Self.formatDuration(t))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - URL

    /// 链接 + 三个操作：复制 / 默认浏览器 / 指定浏览器
    private func urlSection(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(url.absoluteString, systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .help("在浏览器中打开")

            HStack(spacing: 8) {
                Button {
                    copyLink(url)
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                }
                .help("复制地址到剪贴板")

                Button {
                    openWindow(id: "webview", value: command.id)
                } label: {
                    Label("在 App 内打开", systemImage: "macwindow")
                }
                .help("在内置浏览器窗口中打开")

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    browserLabel(title: "默认浏览器", icon: defaultBrowserIcon)
                }
                .help("用系统默认浏览器打开")

                Button {
                    openInPreferredBrowser(url)
                } label: {
                    browserLabel(title: "指定浏览器", icon: preferredBrowserIcon)
                }
                .disabled(preferredBrowserPath.isEmpty)
                .help(preferredBrowserPath.isEmpty
                      ? "尚未设置指定浏览器（设置…中选择）"
                      : "用设置中指定的浏览器打开")
            }
            .buttonStyle(.bordered)
        }
    }

    /// 浏览器按钮内容：实时 App 图标 + 文案（取不到图标时回退 SF Symbol）
    private func browserLabel(title: String, icon: NSImage?) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "safari")
            }
            Text(title)
        }
    }

    /// 系统默认浏览器的实时图标
    private var defaultBrowserIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://")!)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 设置中指定浏览器的实时图标
    private var preferredBrowserIcon: NSImage? {
        guard !preferredBrowserPath.isEmpty else { return nil }
        return NSWorkspace.shared.icon(forFile: preferredBrowserPath)
    }

    private func copyLink(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    private func openInPreferredBrowser(_ url: URL) {
        guard !preferredBrowserPath.isEmpty else { return }
        let appURL = URL(fileURLWithPath: preferredBrowserPath)
        NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - 日志

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(runner.logLines.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .id("log-bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if runner.logLines.isEmpty {
                    Text("输出会显示在这里")
                        .foregroundStyle(.tertiary)
                }
            }
            .onChange(of: runner.logLines.count) { _, _ in
                withAnimation(.none) {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - 工具

    private static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
