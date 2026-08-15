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
            GlassButton("添加命令", systemImage: "plus", fillsWidth: true) {
                model.beginAdd()
            }
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
        HStack(spacing: 10) {
            StatusDot(state: runner.state)
                .padding(.trailing, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(command.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(command.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }
}
