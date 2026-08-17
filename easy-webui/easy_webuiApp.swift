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

        // 内置浏览器：按 commandID 打开（同 ID 复用已有窗口），观察 runner.url 自动刷新
        // （见 WebViewWindow.swift）。WindowGroup(for:) 每个不同 value 一个窗口，
        // 关闭后即销毁内容视图 → WKWebView 释放。
        // 窗口统一以 .hiddenTitleBar 建窗（沉浸式由 SwiftUI 保证内容顶到边缘，
        // 不能在运行时插 styleMask，建窗阶段会被重置成空白条）；
        // "正常"样式由 WebViewWindow 里的 WindowChromeConfigurator 在运行时还原标题栏。
        // （SceneBuilder 不支持普通 if，无法按设置分支建窗。）
        webviewScene().windowStyle(.hiddenTitleBar)

        // 设置：普通窗口（非系统设置浮窗），侧栏按钮与菜单"设置…"都会打开它
        Window("设置", id: WindowID.settings) {
            SettingsView()
        }
        .defaultSize(width: 460, height: 300)

        .commands {
            // 把系统"设置…"菜单项指向普通设置窗口
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    openWindow(id: WindowID.settings)
                }
                .keyboardShortcut(",")
            }
        }
    }

    private func webviewScene() -> some Scene {
        WindowGroup("内置浏览器", id: WindowID.webview, for: UUID.self) { $commandID in
            if let commandID {
                WebViewWindow(commandID: commandID)
                    .environmentObject(model)
            }
        }
        .defaultSize(width: 1024, height: 720)
        .restorationBehavior(.disabled)
    }

    @Environment(\.openWindow) private var openWindow
}
