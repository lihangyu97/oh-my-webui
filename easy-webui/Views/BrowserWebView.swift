import SwiftUI
import WebKit

/// WKWebView 的 SwiftUI 包装：
/// - 持久数据存储：每个服务（command.id）一个独立 WKWebsiteDataStore，
///   localStorage/cookie 等按服务落盘，重启应用/重开窗口不丢；不同服务互不干扰
/// - target="_blank" / window.open：用系统默认浏览器打开（普通链接、跳转仍在窗口内）
/// - runner.url 变化时自动加载新地址（服务重启、端口变更）
struct BrowserWebView: NSViewRepresentable {
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
