import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.selectedID) {
            ForEach(model.commands) { command in
                CommandRowView(runner: model.runtime(for: command), command: command)
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
            .buttonStyle(.borderedProminent)
            .glassEffect(.regular)
            .padding(8)
        }
    }
}

/// 单条命令行：状态点（实时动画）+ 名称/命令。
/// 必须用 @ObservedObject 观察 runner，状态变化才会实时刷新本行。
private struct CommandRowView: View {
    @ObservedObject var runner: WebCLIRunner
    let command: CommandApp

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: runner.state)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.name)
                Text(command.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
    }
}
