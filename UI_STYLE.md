# UI 风格规范（macOS 26 · Liquid Glass 统一系统风格）

> **目标**：所有界面一律使用系统组件与系统渲染，不做自定义控件绘制。
> 这样在新系统（macOS 26+）上自动呈现 Liquid Glass（液态玻璃）外观，
> 在旧系统上自动回退到经典样式，功能与代码都不受影响。

## 硬性规则

1. **控件一律用 SwiftUI 系统组件**：`Button` / `Toggle` / `TextField` / `Form` /
   `NavigationSplitView` / `ToolbarItem` 等。
   **禁止**：自定义绘制控件（自定义 `NSView` 子类、手绘圆角矩形、
   自绘按钮贴图、`Canvas` 绘制交互控件等）。

2. **按钮样式分级**（按操作重要性选择）：
   - 主要操作（启动/停止、添加、保存）→ `.buttonStyle(.borderedProminent)`
   - 次要操作（取消、打开链接）→ 默认样式或 `.buttonStyle(.bordered)`
   - 工具栏/列表行内图标操作 → `.buttonStyle(.borderless)` + SF Symbol
   - 表单默认确认按钮 → `.keyboardShortcut(.defaultAction)`

3. **颜色**：只用 `.accentColor`（全局强调色 #38BDF7）与系统语义色
   （`.red` / `.green` / `.orange` / `.gray` / `.secondary` 等）。
   **禁止硬编码 RGB**（如 `Color(red:green:blue:)`）。

4. **图标**：一律用 SF Symbols（`systemImage:`），不引入图片资源替代。

5. **macOS 26 玻璃效果**：
   - 系统按钮（`.bordered` / `.borderedProminent`）在 macOS 26 上**已自动玻璃化**，
     无需手动处理；
   - **自定义玻璃按钮（胶囊形）**：`.buttonStyle(.plain)` + 
     `.glassEffect(.regular, in: Capsule())`（两端半圆，等同 CSS
     `height: X; border-radius: X/2`），背景色用语义色的**半透明填充**
     加在玻璃内部（`.background(color.opacity(0.18), in: Capsule())`），
     前景用对应语义色（`.foregroundStyle`）——形成 Liquid Glass 彩色玻璃效果；
   - **禁止**在有 tint 背景填充的系统按钮（如 `.borderedProminent` + `.tint`）
     上叠加 `.glassEffect`（tint 背景色会溢出玻璃边框）；

6. **状态指示**：统一使用 `Views/StatusDot.swift`（含运行中涟漪动画），
   禁止在各处散落自画 `Circle` 表示状态。

7. **新增/修改 UI 代码必须符合本规范**；历史代码若与规范冲突，在改动时顺手修正。

## 当前应用清单（已符合本规范）

| 界面元素 | 实现 | 是否符合 |
|----------|------|----------|
| 主布局 / 侧边栏收起 | `NavigationSplitView`（系统自动） | ✅ |
| 详情页工具栏"编辑" | `ToolbarItem` + SF Symbol | ✅ |
| 启动 / 停止 | `.plain` + `Capsule()` 玻璃 + 语义色半透明背景/前景 | ✅ |
| URL 打开 | `.bordered` + `.tint(.blue)` | ✅ |
| 添加命令 | `.plain` + `Capsule()` 玻璃 + accentColor 半透明背景 | ✅ |
| 编辑表单 取消/添加 | 默认系统样式 + `.keyboardShortcut(.defaultAction)` | ✅ |
| 运行状态指示 | `StatusDot`（涟漪动画） | ✅ |
