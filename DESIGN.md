# easy-webui 设计方案（v2 · 轻量版）

> 一个原生 macOS App，用来管理「启动后输出本地 Web 地址」的 CLI 命令
> （如 `npx @deepseek-ai/dsh web`、`opencode`、`vite dev`、`npm run dev` 等）。
> **核心目标只有一个：从命令的输出流里抓到本地地址（如 `dsh web: http://127.0.0.1:3080`），
> 一键启动/停止，并把地址变成可点击按钮打开浏览器。**

v2 与 v1 最大的区别：**不再引入 SwiftTerm 终端模拟器**。既然只关心输出流里的 URL，
用 Foundation 自带的 `Process` + `Pipe` 逐块读 stdout/stderr + 正则扫描即可，
零第三方依赖、包体小、构建快。

---

## 1. 结论

- **可行**，且比"终端模拟器方案"简单一个量级；
- 核心代码：`Process` 起进程 → `readabilityHandler` 异步读 → 按行切分 → 去 ANSI → 正则抓 URL；
- 唯一风险：个别 TUI 程序在非 TTY 环境下不输出地址或拒绝运行（见 §6 验证法与对策）。

## 2. 为什么不需要 SwiftTerm

| 维度 | SwiftTerm（v1） | Process + Pipe（v2） |
|------|-----------------|----------------------|
| 职责 | 完整终端模拟：ANSI 颜色、光标、备用屏幕、可交互 | 只读 stdout/stderr 字节流，抓 URL |
| 包体影响 | 源码编译进二进制，约 **+1~3 MB** | **0** |
| 依赖 | 需引入 SPM 包 | **零依赖** |
| 适用场景 | 要在 App 里"操作"TUI（opencode 全屏界面） | 只要"抓地址 + 看最近几行输出" |
| 主要风险 | 无 | 个别 TUI 程序非 TTY 下行为不同 |

结论：用户不关心终端其它输出 → 不需要终端模拟 → **不引入 SwiftTerm**。
将来若真要嵌入可交互 TUI，再单独加它也不迟（它是纯源码包，加不加都行，互不影响架构）。

## 3. 输出流检测原理

```
Process(/bin/zsh -lic "<命令>")   // -lic：登录+交互式，加载 .zshrc（nvm/alias）
   │  stdout ──▶ Pipe ──▶ readabilityHandler（后台线程，逐块回调）
   │  stderr ──▶ Pipe ──▶ readabilityHandler（同上；很多 CLI 把 URL 打在 stderr）
   ▼
字节流 → 追加到 buffer → 按 "\n" 切成行（保留不完整尾行，防止 URL 被拦腰切断）
   → 每行去 ANSI 转义 → 正则 https?://[^\s\x{1B}\]]+ 提取
   → @Published url 更新 → UI chip 出现 → 点击 NSWorkspace.shared.open(浏览器)
```

关键代码（完整版见工程实现）：

```swift
import Foundation

final class WebCLIRunner: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var state: State = .stopped
    @Published private(set) var recentLog: [String] = []   // 最近 ~100 行（已去 ANSI）

    enum State: Equatable { case stopped, starting, running, stopping, exited(Int32) }

    private var process: Process?
    private var buffer = Data()
    private let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s\x{1B}\]]+"#)

    func start(_ command: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", command]   // 登录+交互式：GUI 环境必须 -lic 才会加载 .zshrc
        p.environment = ProcessInfo.processInfo.environment
        p.environment?["NPM_CONFIG_YES"] = "true"   // 免 npx 首次安装的交互确认

        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.state = proc.terminationStatus == 0 ? .stopped : .exited(proc.terminationStatus)
                self?.process = nil
            }
        }

        for handle in [out.fileHandleForReading, err.fileHandleForReading] {
            handle.readabilityHandler = { [weak self] h in
                let data = h.availableData
                guard !data.isEmpty else { h.readabilityHandler = nil; return }
                self?.consume(data)
            }
        }
        do { try p.run(); process = p; state = .starting }
        catch { state = .exited(-1) }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        let text = String(decoding: buffer, as: UTF8.self)
        var complete: [Substring]
        if text.hasSuffix("\n") {
            complete = text.split(separator: "\n", omittingEmptySubsequences: false)
            buffer.removeAll(keepingCapacity: true)
        } else {
            let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
            complete = parts.dropLast()
            buffer = Data((parts.last ?? "").utf8)   // 尾行可能不完整，留给下次
        }
        for line in complete {
            let clean = Self.stripANSI(String(line))
            DispatchQueue.main.async {
                if let m = self.urlRegex.firstMatch(in: clean,
                        range: NSRange(clean.startIndex..., in: clean)),
                   let r = Range(m.range(at: 0), in: clean),
                   let u = URL(string: String(clean[r])) { self.url = u }
                self.recentLog.append(clean)
                if self.recentLog.count > 100 { self.recentLog.removeFirst(self.recentLog.count - 100) }
            }
        }
    }

    func stop() {
        guard let p = process else { return }
        state = .stopping
        p.interrupt()                               // SIGINT（等价 Ctrl+C）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.process != nil { p.terminate() } // SIGTERM
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if self.process != nil { kill(p.processIdentifier, SIGKILL) }
        }
    }

    private static func stripANSI(_ s: String) -> String {
        // 去掉 CSI 转义（颜色/光标），只留可读文本
        s.replacingOccurrences(of: #"\e\[[0-9;?]*[A-Za-z]"#, with: "",
                               options: .regularExpression)
    }
}
```

要点：
- **stderr 也要监听**——不少 CLI（含 npm 系）把关键输出打在 stderr；
- **缓冲拼接**解决"URL 恰好被一次 read 切成两半"；
- **去 ANSI** 后正则才干净（`\e[32mhttp://...` 这种带色输出直接可匹配）；
- 停止仍用 `SIGINT → SIGTERM → SIGKILL` 递进（v1 的进程组整杀细节可作增强，
  见 §8）。

## 4. 总体架构

```
┌──────────────────────────────────────────────────────────────────┐
│                  easy-webui (macOS · SwiftUI)                    │
│  ┌────────── UI 层 ────────────────────────────────────────────┐ │
│  │ NavigationSplitView                                       │ │
│  │ ├─ 侧栏: 服务列表（状态圆点 ●/○、行内启停开关）             │ │
│  │ └─ 详情: 命令串、状态徽章、▶启动/■停止、                    │ │
│  │        URL chip（★核心）、最近输出（纯文本，去 ANSI）         │ │
│  └───────────────────────────┬───────────────────────────────┘ │
│                              │ @Published: state / url / log    │
│  ┌────────── 状态层 ─────────▼───────────────────────────────┐ │
│  │ AppModel (ObservableObject)                              │ │
│  │ ├─ 命令 CRUD ──▶ AppModel 内联持久化（JSON 文件）      │ │
│  │ └─ 运行时表 [UUID: WebCLIRunner]（每服务一个）              │ │
│  └───────────────────────────┬───────────────────────────────┘ │
│  ┌────────── 进程层 ─────────▼───────────────────────────────┐ │
│  │ WebCLIRunner: Process + Pipe(stdout/stderr)              │ │
│  │   readabilityHandler → 按行 → 去ANSI → 正则抓 URL         │ │
│  │   停止: SIGINT → SIGTERM → SIGKILL                        │ │
│  └───────────────────────────┬───────────────────────────────┘ │
│                              │ /bin/zsh -lic "<命令>"（加载 .zshrc/nvm）│
└──────────────────────────────┼────────────────────────────────┘
                               ▼
              npx @deepseek-ai/dsh web ──► 扫到 http://127.0.0.1:3080
                                         ──► chip 点击 → 默认浏览器打开
```

## 5. UI 效果示意

```
┌───────────────────────────────────────────────────────────────────────────────┐
│  ●  easy-webui                                        ＋ 添加      ⚙ 设置       │
├───────────────────┬───────────────────────────────────────────────────────────┤
│  服务              │  dsh web                                                  │
│                   │  ───────────────────────────────────────────────────────  │
│  ● dsh web        │  状态: ● 运行中     PID 3842     已运行 02:31              │
│    npx @deepseek… │                                                            │
│                   │  [ ■ 停止 ]      [ ↗ http://127.0.0.1:3080 ]   ← 抓到即亮  │
│  ○ opencode       │                                                            │
│    npx opencode   │  ┌─ 最近输出（纯文本）─────────────────────────────────┐   │
│                   │  │ dsh web: http://127.0.0.1:3080                     │   │
│  ○ vite dev       │  │ ▲ Server ready — 在浏览器中打开上面的地址           │   │
│    npm run dev    │  └────────────────────────────────────────────────────┘   │
├───────────────────┴───────────────────────────────────────────────────────────┤
│  ● 2 个服务运行中  ·  1 个已停止                                                  │
└───────────────────────────────────────────────────────────────────────────────┘
```

（去掉了 v1 的终端视图：既然只关心 URL，输出面板降级为"最近 N 行纯文本"，
左上角甚至可以不显示日志，只留状态 + URL。）

## 6. TTY 风险与验证

风险：个别 TUI 程序检测到 stdout 不是终端（`isatty == false`）时会改变行为——
要么退化成纯文本输出（对我们**有利**），要么拒绝运行/不打印地址（不利）。

**20 秒验证法**（对每个要管理的命令跑一次）：

```bash
npx --yes @deepseek-ai/dsh web > /tmp/dsh.log 2>&1 &
sleep 15
cat /tmp/dsh.log        # URL 出现在文件里 → 管道方案可行
kill %1
```

| 验证结果 | 对策 |
|----------|------|
| URL 出现在日志里 | ✅ 管道方案直接可用 |
| 程序拒绝运行/无输出 | ① 用该 CLI 的非交互模式（如 `opencode run`）；② 加一个 ~50 行的 PTY 垫片（`forkpty` 分配伪终端让程序以为有 TTY，但我们仍只读字节流抓 URL，**依然不需要 SwiftTerm**） |

### 实测确认（2026-08-14，本机）

1. **GUI 启动的 App 只继承系统最小 PATH**（`/usr/bin:/bin:/usr/sbin:/sbin`），
   **`zsh -lc` 不加载 `.zshrc`** → 找不到 npx（用户实测报 `zsh:1: command not found: npx`）。
   nvm 装在 `.zshrc`（`.zprofile` 没有），所以命令执行方式必须改为
   **`/bin/zsh -lic "<命令>"`（登录+交互式）**：它会 source `.zshrc`（含 nvm/alias），
   在 `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin` 模拟 GUI 环境下实测可找到 npx ✅。
2. **alias 在非交互 shell 中不生效**：`zsh -lic` 下 alias 可用，但为明确起见，
   App 内仍存展开后的完整命令（用户已确认执行 `npx @deepseek-ai/dsh web` 本身）。
3. **端口占用是真实场景**：3080 已被运行中的 dsh web 占用时，再启动报
   `EADDRINUSE: address already in use 127.0.0.1:3080` 并退出。
   → App 需显示退出码 + stderr；增强：检测到 "EADDRINUSE" 时直接提示"该地址已在运行，
   是否打开浏览器？"（URL 先亮出来）。
4. **dsh 安装状态**：本机 `~/.npm/_npx` 已有可用 rc.6 安装；干净缓存下 `npx @deepseek-ai/dsh web`
   可能因 registry 发布不一致（`@deepseek-ai/dsh-subprocess@^0.1.0-rc.6` 不存在 → ETARGET）装不上。
   与 App 无关，但再次说明"显示 stderr/退出码"的必要性。

## 7. 数据模型与状态机

> **工作目录（已实测核实）**：dsh 的会话工作区**不是** `dsh web` 的启动目录——
> 会话按工作区路径存于 `~/.dsh/sessions/<路径编码>/`，agent 的 cwd 取自会话 header
> （实测 header 为 `"cwd":"/Users/lihangyu/workspace/..."`，由 web UI 里选择/创建工作区决定）。
> 启动目录只影响两件小事：相对配置文件的解析、从启动目录加载 `.env`。
> **例外：`dsh run <task>`（headless 一次性模式）的 agent cwd = `process.cwd()`（启动目录）**，
> 这类命令才真正依赖 App 的工作目录设置。App 内未配置 `workingDirectory` 时默认用户主目录
> （GUI 启动的 App 默认 cwd 是 `/`，主目录是安全兜底；每条命令可在编辑表单里单独指定）。

```swift
struct CommandApp: Codable, Identifiable {
    var id = UUID()
    var name: String                 // "dsh web"
    var command: String              // "npx @deepseek-ai/dsh web"
    var workingDirectory: String?    // 可选
    var environment: [String: String] = [:]
    var autoStart: Bool = false      // App 启动时自动拉起
    var restartOnExit: Bool = false  // 退出后自动重启
}
```

> **首次运行行为**：默认**空列表**（无内置命令），全部由用户手动添加；
> 命令持久化于 `~/Library/Application Support/easy-webui/commands.json`，
> 每次增删改时整体覆写（Codable + 原子写入）。

```
            start                 spawn 成功
  stopped ────────▶ starting ───────────────▶ running
     ▲                │                         │
     │                │ spawn 失败               │ 进程退出
     │                ▼                         ▼
     │             crashed ◀────────────── exited(code)
     │              (显示退出码+stderr)          (npx 下载失败、端口占用等)
     └─────────── 再次点击 start ───────────────┘
  running ── 点停止 ──▶ stopping ── SIGINT→SIGTERM→2s→SIGKILL ──▶ stopped
```

## 8. 进程树清理（增强项）

`npx` 是 wrapper，node 服务是它的子进程；只杀父进程会留孤儿占着 3080 端口。
基础版用 `interrupt()/terminate()/kill` 递进即可；要更干净可让子进程成为
进程组组长后用 `kill(-pgid, sig)` 整组杀（用 `posix_spawn` + `POSIX_SPAWN_SETPGROUP`
实现，几十行代码，仍零依赖）。

## 9. 关键决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 输出检测 | `Process` + `Pipe` + 正则 | 零依赖、包体最小，满足"只抓 URL" |
| 终端模拟 | **不引入 SwiftTerm** | 不需要渲染 TUI；省 ~1-3 MB 包体与一个 SPM 依赖 |
| 命令环境 | `/bin/zsh -lic "<命令>"` | GUI 只有最小 PATH；-lic 才会 source .zshrc（nvm/alias） |
| 防交互挂起 | 环境变量 `NPM_CONFIG_YES=true` | npx 首次安装不再问 "Ok to proceed?" |
| 停止策略 | SIGINT→SIGTERM→SIGKILL（可升级整组杀） | 优雅停止 + 兜底强杀 |
| 持久化 | JSON + Codable（Application Support/） | 结构简单、免迁移、可手改 |
| App Sandbox | 关闭 | 需 spawn 任意进程、读 shell 环境 |
| 链接打开 | `NSWorkspace.shared.open` | 点击 URL chip 开默认浏览器 |

## 10. 工程结构

```
easy-webui/
├── easy_webuiApp.swift          # App 入口，注入 AppModel
├── ContentView.swift            # NavigationSplitView 主布局
├── Assets.xcassets/             # AppIcon（10 尺寸 PNG）+ AccentColor（#38BDF7）
├── Models/
│   ├── CommandApp.swift         # Codable 命令模型
│   └── RunState.swift           # 运行状态枚举
├── Services/
│   ├── AppModel.swift           # 状态中枢（列表 + 运行时表）+ JSON 持久化内联
│   └── WebCLIRunner.swift       # Process+Pipe 起停 / 输出扫描 / 去 ANSI（核心，~170 行）
└── Views/
    ├── SidebarView.swift
    ├── CommandDetailView.swift  # 启停 / 状态 / URL chip
    └── CommandEditorSheet.swift # 添加/编辑表单

scripts/
└── generate_app_icon.sh         # 从一张 1024×1024 主图生成 AppIcon 全部 10 个尺寸
```

**资源与外观**：App 图标采用**传统 10 槽位** AppIcon（16/32/128/256/512 各 1x、2x，
共 10 个 PNG），由 `scripts/generate_app_icon.sh` 从一张 1024×1024 主图一键生成；
全局强调色 `AccentColor` 为 **#38BDF7**（sRGB，`AccentColor.colorset`），
代码中通过 `.accentColor` 引用。

## 11. 路线图

- **Phase 0 · 验证**：对目标命令跑 §6 的 20 秒验证法，确认管道方案可行
- **Phase 1 · 核心**：`WebCLIRunner` + 状态机 + URL 扫描（先做出能抓 `dsh web` 地址的 Demo）
- **Phase 2 · 界面**：侧栏 CRUD + 详情页 + URL chip 点击开浏览器 + JSON 持久化
- **Phase 3 · 打磨**：优雅停止（整组杀）、自动重启、崩溃提示、状态栏

## 12. 内置浏览器窗口（WKWebView）

> 详情页 URL 区域新增"在 App 内打开"按钮（位于"复制链接"与"默认浏览器"之间），
> 点击后打开独立窗口内嵌 WKWebView 加载该服务的当前地址，无需跳外部浏览器。

**实现要点**（`easy-webui/Views/WebViewWindow.swift` + `easy_webuiApp.swift` 的
`WindowGroup("内置浏览器", id: "webview", for: UUID.self)`）：

> 窗口样式可在设置页切换（`@AppStorage("webWindowStyle")`，改完即时生效）：
> - **正常**：标准标题栏（标题 + 红绿灯），无工具栏按钮、无地址栏
> - **沉浸式**：隐藏标题栏与红绿灯，WKWebView 顶到窗口边缘；顶部留 24pt 隐形
>   拖拽条（`mouseDownCanMoveWindow`）保证可拖动，关窗用 ⌘W / 菜单
>
> **实现要点**：窗口**统一由场景层以 `.windowStyle(.hiddenTitleBar)` 建窗**（沉浸式
> 由 SwiftUI 保证内容顶到边缘）。不能在标准窗口上运行时插 `.fullSizeContentView`——
> SwiftUI 建窗阶段会重置 styleMask，结果只剩一条空白标题栏（实测踩坑）。
> "正常"样式由 `WindowChromeConfigurator`（背景零尺寸 NSView）在运行时**还原**
> 标题栏：移除 `.fullSizeContentView`、`titlebarAppearsTransparent=false`、
> `titleVisibility=.visible`、红绿灯显隐；SwiftUI 只在建窗时设置一次 styleMask，
> 之后的改动不会被覆盖，所以还原方向可靠、设置切换对已打开窗口即时生效。
> （另：本 SDK 的 SceneBuilder 不支持普通 if 语句，无法按设置分支建窗，故统一
> hiddenTitleBar 再还原是唯一稳妥路径。）
>
> **两个实测坑（已修）**：
> 1. 即使 fullSizeContentView 生效，SwiftUI 内容仍从标题栏安全区下方开始渲染，
>    顶部会透出窗口背景成一条白色"标题栏"→ 内容必须 `.ignoresSafeArea()`。
> 2. 拖拽条若用 VStack 叠在内容上方会把内容挤下去 → 改用 ZStack **悬浮覆盖**
>    （`mouseDownCanMoveWindow` 的 24pt 透明条在最上层），内容才能真正到顶。
> 3. **先正常后切沉浸式**会丢 `.fullSizeContentView`（正常模式移除后没补回）→
>    沉浸式分支必须 `styleMask.insert(.fullSizeContentView)`（实测 styleMask
>    15 → 32783 后内容才重新顶到边缘）。

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 窗口形态 | `WindowGroup(for: UUID.self)`，按 **commandID** 打开 | 每个服务一个窗口；同服务重复点击复用已有窗口（`openWindow(id:value:)`）；关窗即销毁内容视图 → WKWebView 释放 |
| 内存策略 | **按需创建、关闭即销毁**，无常驻 | 每个开着的窗口 = 1 个 WebKit 渲染进程；关掉由系统回收（有短暂延迟但不泄漏），不随服务数常驻 |
| URL 跟随 | 观察 runner.url，变化时重新加载 | 服务重启/端口变更后窗口自动刷新到新地址，不产生孤儿窗口 |
| 数据存储 | `WKWebsiteDataStore.nonPersistent()` | 每次开窗口全新会话，cookie/localStorage 不留盘 |
| 新窗口链接 | `WKUIDelegate.createWebViewWith` 返回 nil + 当前 WebView 跳转 | target=_blank / window.open 一律同窗口跳转，简单顺手 |
| 关窗清理 | `CleanupWebView.viewWillMove(toWindow: nil)` 时 `stopLoading()` | 停掉进行中加载，让渲染进程尽快回收 |
| 状态恢复 | `.restorationBehavior(.disabled)` | 避免重启后恢复出指向已删除命令的孤儿窗口 |

应用体积影响 ≈ 0（WebKit 为系统框架，动态链接）；内存与 Safari 标签页同引擎、基本持平，
省的是浏览器 UI 进程；相对 Electron/CEF 则省整个 Chromium 运行时（几百 MB 级）。

