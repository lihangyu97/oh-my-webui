import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

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
            .onMove(perform: model.move)
        }
        .navigationTitle("服务")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                // 固定宽度胶囊按钮：不随侧栏宽度拉伸（fillsWidth 会导致
                // 侧栏窄时缩成圆、宽时拉得很长）
                GlassButton("添加命令", systemImage: "plus", minWidth: 84) {
                    model.beginAdd()
                }
                Spacer(minLength: 0)

                // 圆形玻璃设置按钮，打开设置窗口（整圆均可点击）
                Button {
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Circle())
                .help("设置")
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
