import SwiftUI
import AppKit

/// 内置浏览器窗口样式（设置页可选）
enum WebWindowStyle: String, CaseIterable, Identifiable {
    case normal
    case immersive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: "正常（显示标题栏）"
        case .immersive: "沉浸式（隐藏标题栏）"
        }
    }
}

/// 独立"内置浏览器"窗口：按 commandID 打开，观察 runner 的 url 变化自动刷新。
/// 窗口关闭 = SwiftUI Window scene 销毁视图树 → WKWebView 释放 + stopLoading，
/// 渲染进程由 WebKit 回收（有短暂延迟但不会泄漏），不做常驻。
struct WebViewWindow: View {
    let commandID: UUID
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let command = model.commands.first(where: { $0.id == commandID }) {
            WebViewWindowContent(command: command, runner: model.runtime(for: command))
        } else {
            ContentUnavailableView(
                "服务不存在或已删除",
                systemImage: "questionmark.square.dashed"
            )
        }
    }
}

/// 窗口内容：WKWebView 全屏填充，无任何工具条/地址栏（标题栏只留标题+红绿灯）。
/// 刷新、复制、外部浏览器打开等功能主窗口已有，这里保持纯粹。
/// 样式由设置页控制：正常（标准标题栏）或沉浸式（隐藏标题栏+红绿灯，顶部留隐形拖拽条）。
private struct WebViewWindowContent: View {
    let command: CommandApp
    @ObservedObject var runner: WebCLIRunner
    @AppStorage(AppStorageKey.webWindowStyle) private var styleRaw = WebWindowStyle.normal.rawValue

    private var immersive: Bool { styleRaw == WebWindowStyle.immersive.rawValue }

    var body: some View {
        // 沉浸式：内容必须 .ignoresSafeArea() 才会顶到窗口边缘——
        // 实测发现即使 fullSizeContentView 生效，SwiftUI 内容仍从标题栏
        // 安全区下方开始渲染，顶部会透出窗口背景成一条白色标题栏。
        // 拖拽条用 ZStack 悬浮覆盖，内容才能真正到顶。
        ZStack(alignment: .top) {
            Group {
                if let url = runner.url {
                    BrowserWebView(url: url, storeIdentifier: command.id)
                } else {
                    ContentUnavailableView(
                        "暂无地址",
                        systemImage: "link",
                        description: Text("等待服务输出地址…")
                    )
                }
            }
            if immersive {
                // 沉浸式下标题栏不可拖，顶部悬浮一条 24pt 隐形拖拽条
                DragStrip()
                    .frame(height: 24)
            }
        }
        .ignoresSafeArea(immersive ? .all : [])
        .background(WindowChromeConfigurator(immersive: immersive))
        .navigationTitle(command.name)
    }
}
