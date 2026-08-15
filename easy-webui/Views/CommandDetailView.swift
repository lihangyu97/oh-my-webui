import SwiftUI
import AppKit

struct CommandDetailView: View {
    @EnvironmentObject var model: AppModel
    let command: CommandApp
    @ObservedObject var runner: WebCLIRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            if let url = runner.url {
                urlButton(url)
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
        }
    }

    // MARK: - 启停 / 状态

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                model.toggle(command)
            } label: {
                Label(runner.isRunning ? "停止" : "启动",
                      systemImage: runner.isRunning ? "stop.fill" : "play.fill")
                    .foregroundStyle(runner.isRunning ? Color.red : Color.accentColor)
                    .frame(minWidth: 84)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))

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

    private func urlButton(_ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(url.absoluteString, systemImage: "arrow.up.right.square")
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .help("在浏览器中打开")
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
