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
