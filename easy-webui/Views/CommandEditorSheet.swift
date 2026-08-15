import SwiftUI
import AppKit

struct CommandEditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let editing: CommandApp?        // nil = 新增

    @State private var name = ""
    @State private var command = ""
    @State private var workingDirectory = ""
    @State private var autoStart = false
    @State private var restartOnExit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "添加命令" : "编辑命令")
                .font(.title3.bold())

            Form {
                TextField("名称", text: $name)
                TextField("命令", text: $command,
                          prompt: Text("npx @deepseek-ai/dsh web"))
                    .font(.system(.body, design: .monospaced))
                HStack(spacing: 8) {
                    TextField("工作目录（可选）", text: $workingDirectory)
                    Button {
                        chooseWorkingDirectory()
                    } label: {
                        Label("选择…", systemImage: "folder")
                    }
                    .help("用 Finder 选择工作目录")
                }
                Toggle("App 启动时自动运行", isOn: $autoStart)
                Toggle("退出后自动重启", isOn: $restartOnExit)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(editing == nil ? "添加" : "保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            name = editing?.name ?? ""
            command = editing?.command ?? ""
            workingDirectory = editing?.workingDirectory ?? ""
            autoStart = editing?.autoStart ?? false
            restartOnExit = editing?.restartOnExit ?? false
        }
    }

    /// 唤起 Finder（NSOpenPanel）选择工作目录，选中后回填输入框
    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.title = "选择工作目录"
        if !workingDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func save() {
        let wd = workingDirectory.isEmpty ? nil : workingDirectory
        if let editing {
            model.update(CommandApp(
                id: editing.id,
                name: name,
                command: command,
                workingDirectory: wd,
                environment: editing.environment,
                autoStart: autoStart,
                restartOnExit: restartOnExit
            ))
        } else {
            model.add(CommandApp(
                name: name,
                command: command,
                workingDirectory: wd,
                autoStart: autoStart,
                restartOnExit: restartOnExit
            ))
        }
        dismiss()
    }
}
