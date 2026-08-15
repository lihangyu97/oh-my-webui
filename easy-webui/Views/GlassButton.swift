import SwiftUI

/// 统一玻璃胶囊按钮（macOS 26 Liquid Glass 风格）
///
/// 两端半圆（Capsule）+ 语义色半透明玻璃背景，所有主操作按钮一律使用本组件
/// （规范见 UI_STYLE.md）。
///
/// 用法：
/// ```swift
/// GlassButton("启动", systemImage: "play.fill", tint: .green, minWidth: 84) {
///     model.toggle(command)
/// }
/// GlassButton("添加命令", systemImage: "plus") {
///     model.beginAdd()
/// }
/// ```
struct GlassButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = .accentColor
    var minWidth: CGFloat?
    var fillsWidth = false
    let action: () -> Void

    init(_ title: String,
         systemImage: String? = nil,
         tint: Color = .accentColor,
         minWidth: CGFloat? = nil,
         fillsWidth: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.minWidth = minWidth
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .foregroundStyle(tint)
            .frame(minWidth: minWidth,
                   maxWidth: fillsWidth ? .infinity : nil)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(tint.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule())
    }
}
