import SwiftUI
import AppKit
import WebKit

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
    @AppStorage("webWindowStyle") private var styleRaw = WebWindowStyle.normal.rawValue

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

/// 按设置控制窗口外观。窗口统一由场景层以 .hiddenTitleBar 建窗（沉浸基础），
/// 这里负责：
/// - 沉浸式：隐藏红绿灯（标题栏本就不可见）
/// - 正常：还原标准标题栏（移除 fullSizeContentView + 透明、恢复标题与红绿灯）
/// 注意不能反过来——在标准窗口上运行时插 .fullSizeContentView 会被 SwiftUI
/// 建窗阶段重置，只剩一条空白标题栏。SwiftUI 只在建窗时设置一次 styleMask，
/// 之后这里的改动不会被覆盖，所以"还原"方向是可靠的，设置切换即时生效。
private struct WindowChromeConfigurator: NSViewRepresentable {
    let immersive: Bool

    func makeNSView(context: Context) -> ChromeConfigView {
        ChromeConfigView()
    }

    func updateNSView(_ nsView: ChromeConfigView, context: Context) {
        nsView.immersive = immersive
    }

    /// 真正改 NSWindow 外观的视图
    final class ChromeConfigView: NSView {
        var immersive = false {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // SwiftUI 建窗流程可能晚于视图挂载，下一轮 runloop 再补一次
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard let window else { return }
            if immersive {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                // 关键：正常模式移除过 fullSizeContentView，切回沉浸式必须补回，
                // 否则内容无法延伸到标题栏下，顶部又是一条白色标题栏
                window.styleMask.insert(.fullSizeContentView)
            } else {
                window.titlebarAppearsTransparent = false
                window.titleVisibility = .visible
                window.styleMask.remove(.fullSizeContentView)
            }
            for type in [NSWindow.ButtonType.closeButton,
                         .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = immersive
            }
        }
    }
}

/// 沉浸式下的隐形拖拽条：鼠标按下即拖动整个窗口
private struct DragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> DragStripView {
        DragStripView()
    }

    func updateNSView(_ nsView: DragStripView, context: Context) {}

    final class DragStripView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

/// WKWebView 的 SwiftUI 包装：
/// - 持久数据存储：每个服务（command.id）一个独立 WKWebsiteDataStore，
///   localStorage/cookie 等按服务落盘，重启应用/重开窗口不丢；不同服务互不干扰
/// - target="_blank" / window.open：用系统默认浏览器打开（普通链接、跳转仍在窗口内）
/// - runner.url 变化时自动加载新地址（服务重启、端口变更）
private struct BrowserWebView: NSViewRepresentable {
    let url: URL
    let storeIdentifier: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 按服务持久化的数据存储：identifier 固定为该命令的 id（commands.json 中持久化，
        // 重启不变），因此同一服务的 localStorage/cookie 跨窗口、跨启动保留
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeIdentifier)
        // 只允许"用户手势触发的" window.open / target=_blank（会走 createWebViewWith →
        // 默认浏览器）；无手势的自动弹窗静默拦截，避免默认浏览器被刷标签页
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = CleanupWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // URL 变化（服务重启后新地址）→ 重新加载
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        /// 最近已交给系统浏览器打开的 URL（防止同一导航被两个代理各触发一次而重复打开）
        private var recentlyOpened: [(url: URL, date: Date)] = []

        /// 交给系统默认浏览器打开（带 2 秒内去重）
        private func openExternally(_ url: URL) {
            let now = Date()
            recentlyOpened.removeAll { now.timeIntervalSince($0.date) > 2 }
            guard !recentlyOpened.contains(where: { $0.url == url }) else { return }
            recentlyOpened.append((url, now))
            NSWorkspace.shared.open(url)
        }

        /// WKUIDelegate：target=_blank / window.open（用户手势）→ 默认浏览器，不开新窗口
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                openExternally(url)
            }
            return nil
        }

        /// WKNavigationDelegate：目标是新窗口/新 frame 的导航 → 默认浏览器并取消
        /// （兜底 createWebViewWith 未触发的场景，配合 openExternally 去重）
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                openExternally(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// 关窗（视图移出窗口）时停掉加载，让 WebKit 尽快回收渲染进程
private final class CleanupWebView: WKWebView {
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopLoading()
        }
    }
}
