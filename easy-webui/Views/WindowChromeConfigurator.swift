import SwiftUI
import AppKit

/// 按设置控制窗口外观。窗口统一由场景层以 .hiddenTitleBar 建窗（沉浸基础），
/// 这里负责：
/// - 沉浸式：隐藏红绿灯（标题栏本就不可见）
/// - 正常：还原标准标题栏（移除 fullSizeContentView + 透明、恢复标题与红绿灯）
/// 注意不能反过来——在标准窗口上运行时插 .fullSizeContentView 会被 SwiftUI
/// 建窗阶段重置，只剩一条空白标题栏。SwiftUI 只在建窗时设置一次 styleMask，
/// 之后这里的改动不会被覆盖，所以"还原"方向是可靠的，设置切换即时生效。
struct WindowChromeConfigurator: NSViewRepresentable {
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
struct DragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> DragStripView {
        DragStripView()
    }

    func updateNSView(_ nsView: DragStripView, context: Context) {}

    final class DragStripView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
