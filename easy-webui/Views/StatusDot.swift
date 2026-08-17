import SwiftUI

/// 运行状态指示点：running 时绿色圆点向外一圈圈扩散（涟漪脉冲动画）。
/// animated = false 时 running 只显示静态绿点——用于非选中行，避免多个
/// 常驻 repeatForever 动画叠加（服务多时省 GPU 合成开销）。
struct StatusDot: View {
    let state: RunState
    var size: CGFloat = 8
    var animated = true

    @State private var pulsing = false

    private var color: Color {
        switch state {
        case .running: .green
        case .starting, .stopping: .orange
        case .exited: .red
        case .stopped: .gray
        }
    }

    var body: some View {
        ZStack {
            if state == .running && animated {
                pulseRing(delay: 0)
                pulseRing(delay: 0.9)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: max(size * 3, 20), height: max(size * 3, 20))
        .onAppear { update(state) }
        .onChange(of: state) { _, new in update(new) }
    }

    private func update(_ new: RunState) {
        pulsing = (new == .running)
    }

    private func pulseRing(delay: Double) -> some View {
        Circle()
            .stroke(color.opacity(0.45), lineWidth: 1.5)
            .frame(width: size, height: size)
            .scaleEffect(pulsing ? 2.8 : 1.0)
            .opacity(pulsing ? 0 : 0.6)
            .animation(
                pulsing
                    ? .easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(delay)
                    : .default,
                value: pulsing
            )
    }
}
