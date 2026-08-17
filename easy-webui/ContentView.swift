import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let cmd = model.selectedCommand {
                CommandDetailView(command: cmd, runner: model.runtime(for: cmd))
            } else {
                ContentUnavailableView(
                    "选择左侧服务",
                    systemImage: "terminal",
                    description: Text("或点击左下角 ＋ 添加一条启动命令")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        // 窗口最小尺寸：防止窗口缩得过小导致 macOS 把侧栏压过 220 下限，
        // 挤压左下角添加/设置按钮（min: 220 只约束拖拽，不约束窗口缩放）
        .frame(minWidth: 560, minHeight: 420)
        .sheet(isPresented: $model.presentEditor) {
            CommandEditorSheet(editing: model.editorTarget)
                .environmentObject(model)
        }
        .task {
            model.autoStartOnce()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.stopAll()
        }
    }
}
