import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    /// 折叠的组（key 为 CommandSection.id）；会话内有效，不持久化
    @State private var collapsedKeys: Set<String> = []

    var body: some View {
        List(selection: $model.selectedID) {
            ForEach(model.commandSections) { group in
                // Section(isExpanded:) 是 macOS 14+ 原生可折叠 Section：
                // 展开/收起动画由系统处理（手动 if 条件渲染没有动画）
                Section(isExpanded: isExpandedBinding(for: group.id)) {
                    ForEach(group.commands) { command in
                        CommandRowView(runner: model.runtime(for: command), command: command)
                            .tag(command.id)
                            .contextMenu {
                                Button("编辑…") { model.beginEdit(command) }
                                Button("删除", role: .destructive) { model.remove(command) }
                            }
                    }
                    .onMove(perform: moveRow)
                } header: {
                    GroupHeaderView(group: group)
                }
            }
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

    /// Section(isExpanded:) 的绑定：默认全部展开（collapsedKeys 为空）。
    /// 系统在绑定变化时自行动画展开/收起，无需 withAnimation。
    private func isExpandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedKeys.contains(id) },
            set: { expanded in
                if expanded {
                    collapsedKeys.remove(id)
                } else {
                    collapsedKeys.insert(id)
                }
            }
        )
    }

    /// 行拖拽重排。onMove 回调的索引是"整个 List 可见行的全局索引"，
    /// 折叠组不渲染会导致可见索引 ≠ 数组索引，故先映射回数组索引再移动。
    /// 跨组拖拽放下后命令会按 workingDirectory 重新归组，表现为自然回弹（不支持跨组）。
    private func moveRow(from source: IndexSet, to destination: Int) {
        let visibleIndices = model.commandSections.flatMap { group in
            collapsedKeys.contains(group.id)
                ? []
                : group.commands.compactMap { cmd in model.commands.firstIndex(of: cmd) }
        }
        guard let s = source.first, s < visibleIndices.count else { return }
        let src = visibleIndices[s]
        let dest = destination < visibleIndices.count ? visibleIndices[destination] : model.commands.count
        model.move(from: IndexSet(integer: src), to: dest)
    }
}

/// 组头：目录最后两级文件夹名。
/// 折叠/展开由 Section(isExpanded:) 系统处理（点击组头即切换），系统自带
/// disclosure 箭头，这里不画额外指示；tooltip 显示完整路径（未设置组显示 home 路径）。
private struct GroupHeaderView: View {
    let group: CommandSection

    var body: some View {
        HStack(spacing: 5) {
            Text(group.title)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)   // 组头加高：更好点击
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(group.tooltip)
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
