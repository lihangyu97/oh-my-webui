//
//  easy_webuiApp.swift
//  easy-webui
//
//  Created by lihangyu on 2026/8/14.
//

import SwiftUI

@main
struct easy_webuiApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("EasyWebUI") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 920, height: 600)

        // 设置：普通窗口（非系统设置浮窗），侧栏按钮与菜单"设置…"都会打开它
        Window("设置", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 460, height: 300)

        .commands {
            // 把系统"设置…"菜单项指向普通设置窗口
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",")
            }
        }
    }

    @Environment(\.openWindow) private var openWindow
}
