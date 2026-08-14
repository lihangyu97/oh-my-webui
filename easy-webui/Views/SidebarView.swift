import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.selectedID) {
            ForEach(model.commands) { command in
                row(for: command)
                    .tag(command.id)
                    .contextMenu {
                        Button("编辑…") { model.beginEdit(command) }
                        Button("删除", role: .destructive) { model.remove(command) }
                    }
            }
        }
        .navigationTitle("服务")
        .safeAreaInset(edge: .bottom) {
            Button {
                model.beginAdd()
            } label: {
                Label("添加命令", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func row(for command: CommandApp) -> some View {
        let runner = model.runtime(for: command)
        return HStack(spacing: 8) {
            Circle()
                .fill(color(for: runner.state))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.name)
                Text(command.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button {
                model.toggle(command)
            } label: {
                Image(systemName: runner.isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .foregroundStyle(runner.isRunning ? Color.red : Color.green)
            }
            .buttonStyle(.borderless)
            .help(runner.isRunning ? "停止" : "启动")
        }
    }

    private func color(for state: RunState) -> Color {
        switch state {
        case .running: .green
        case .starting, .stopping: .orange
        case .exited: .red
        case .stopped: .gray
        }
    }
}
