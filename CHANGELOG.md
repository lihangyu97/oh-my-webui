# Changelog

## [Unreleased]

### 工程优化（重构 + 测试 + 性能）

- **代码组织**
  - `AppModel` 按职责拆为四个文件：核心状态 + `AppModel+Runtime`（进程启停）+ `AppModel+Commands`（CRUD/分组）+ `AppModel+Persistence`（JSON 持久化）
  - `CommandSection` 归位到 `Models/`；新增 `Models/AppConstants.swift`（窗口 id、AppStorage key、bundle id 兜底集中管理，替换散落字符串）
  - `WebViewWindow.swift` 拆为三个文件：窗口壳 / `BrowserWebView`（WKWebView 包装）/ `WindowChromeConfigurator`（窗口外观）
  - 新增 `easy-webuiTests` 单元测试 target 与共享 scheme

- **性能**
  - 日志解析移出主线程：新增 `OutputParser`（nonisolated，串行队列切行/去 ANSI），主线程只更新 `@Published`；URL 提取提成可测纯函数 `WebCLIRunner.firstURL`
  - 正则预编译为 `static let`（URL / ANSI），不再每行编译
  - `stop()` 的延时闭包改为捕获 `Process` 而非 `self`：删除命令后不再用强引用延长 runner 生命周期，进程清理仍保证执行
  - 状态涟漪动画只作用于选中行（`StatusDot.animated`），非选中运行行静态圆点

- **健壮性**
  - `commands.json` 读写失败用 `os_log` 记录（不再静默吞掉）

- **测试**（`easy-webuiTests`）
  - `CommandSection`：组名两级/单级/根/尾斜杠/nil 边界
  - 分组：有序分组、组顺序、空列表
  - `OutputParser`：跨块切行、去 ANSI、URL 不被拦腰切断、空块、未收尾行
  - `WebCLIRunner.firstURL`：HTTP/HTTPS/非 HTTP/多个 URL/ANSI 邻接

- **CI**：`build-dmg.yml` 增加单元测试步骤

## 历史

见 git 提交历史。
