import SwiftUI

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
                TextField("工作目录（可选）", text: $workingDirectory)
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
